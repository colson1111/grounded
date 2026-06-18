import Foundation
import AVFoundation
import CoreImage
import Vision
import Combine

class ObjectRecognitionManager: NSObject, ObservableObject {
    static let shared = ObjectRecognitionManager()

    @Published var isScanning = false
    @Published var topResults: [(label: String, confidence: Float)] = []

    var detectedLabel: String { topResults.first?.label ?? "" }
    var detectedConfidence: Float { topResults.first?.confidence ?? 0 }

    // When true, detection results are reported but profiles are not activated.
    // Used when testing triggers from the profile editor.
    var activationEnabled = true

    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.craig.grounded.camera.session")
    private let bufferLock = NSLock()
    private var latestPixelBuffer: CVPixelBuffer?
    private var debounceTimer: Timer?
    private var lastActivatedProfileID: String?
    private var isSessionConfigured = false
    private let ciContext = CIContext()

    private override init() {
        super.init()
    }

    private func ensureSessionConfigured() {
        guard !isSessionConfigured else { return }
        isSessionConfigured = true
        setupSession()
    }

    private func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.captureSession.beginConfiguration()
            if self.captureSession.canSetSessionPreset(.high) {
                self.captureSession.sessionPreset = .high
            } else {
                self.captureSession.sessionPreset = .medium
            }

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                self.captureSession.canAddInput(input)
            else {
                self.captureSession.commitConfiguration()
                return
            }
            self.captureSession.addInput(input)

            try? device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()

            self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            if self.captureSession.canAddOutput(self.videoOutput) {
                self.captureSession.addOutput(self.videoOutput)
            }
            self.captureSession.commitConfiguration()
        }
    }

    func startScanning(activationEnabled: Bool = true) {
        self.activationEnabled = activationEnabled
        ensureSessionConfigured()
        sessionQueue.async { [weak self] in
            self?.captureSession.startRunning()
        }
        DispatchQueue.main.async { self.isScanning = true }
    }

    func stopScanning() {
        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }
        bufferLock.lock()
        latestPixelBuffer = nil
        bufferLock.unlock()
        DispatchQueue.main.async {
            self.isScanning = false
            self.topResults = []
            self.lastActivatedProfileID = nil
        }
    }

    /// Anchor setup: center-crop + full frame, lower threshold, more candidates.
    func classifyLatestFrame(forAnchorCapture: Bool = true) async -> [(label: String, confidence: Float)] {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: [])
                    return
                }

                self.bufferLock.lock()
                guard let pixelBuffer = self.latestPixelBuffer else {
                    self.bufferLock.unlock()
                    continuation.resume(returning: [])
                    return
                }
                self.bufferLock.unlock()

                let minConfidence: Float = forAnchorCapture ? 0.01 : 0.05
                let maxResults = forAnchorCapture ? 40 : 15
                let buffers: [CVPixelBuffer]
                if forAnchorCapture,
                   let cropped = self.centerCroppedPixelBuffer(from: pixelBuffer, fraction: 0.72) {
                    buffers = [cropped, pixelBuffer]
                } else {
                    buffers = [pixelBuffer]
                }

                let results = self.rankClassifications(
                    in: buffers,
                    minConfidence: minConfidence,
                    maxResults: maxResults
                )
                continuation.resume(returning: results)
            }
        }
    }

    private func rankClassifications(
        in buffers: [CVPixelBuffer],
        minConfidence: Float,
        maxResults: Int
    ) -> [(label: String, confidence: Float)] {
        var scores: [String: Float] = [:]

        for (index, buffer) in buffers.enumerated() {
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up)
            try? handler.perform([request])

            guard let observations = request.results as? [VNClassificationObservation] else { continue }
            let cropBoost: Float = index == 0 && buffers.count > 1 ? 1.15 : 1.0
            for observation in observations where !VisionLabelCatalog.isExcluded(observation.identifier) {
                let boosted = min(observation.confidence * cropBoost, 1.0)
                let key = observation.identifier
                scores[key] = max(scores[key] ?? 0, boosted)
            }
        }

        return scores
            .filter { $0.value >= minConfidence }
            .sorted { $0.value > $1.value }
            .prefix(maxResults)
            .map { (label: $0.key, confidence: $0.value) }
    }

    private func centerCroppedPixelBuffer(from source: CVPixelBuffer, fraction: CGFloat) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: source)
        let extent = ciImage.extent
        guard extent.width > 1, extent.height > 1 else { return nil }

        let cropWidth = extent.width * fraction
        let cropHeight = extent.height * fraction
        let cropRect = CGRect(
            x: extent.midX - cropWidth / 2,
            y: extent.midY - cropHeight / 2,
            width: cropWidth,
            height: cropHeight
        )

        let cropped = ciImage.cropped(to: cropRect)
        var output: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(cropWidth),
            Int(cropHeight),
            CVPixelBufferGetPixelFormatType(source),
            nil,
            &output
        )
        guard status == kCVReturnSuccess, let output else { return nil }
        ciContext.render(cropped, to: output)
        return output
    }
}

extension ObjectRecognitionManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        bufferLock.lock()
        latestPixelBuffer = pixelBuffer
        bufferLock.unlock()

        let request = VNClassifyImageRequest { [weak self] req, _ in
            guard let self,
                  let results = req.results as? [VNClassificationObservation]
            else { return }

            let top = results
                .filter { $0.confidence > 0.05 && !VisionLabelCatalog.isExcluded($0.identifier) }
                .prefix(8)
                .map { (label: $0.identifier, confidence: $0.confidence) }

            DispatchQueue.main.async {
                self.topResults = Array(top)
                if self.activationEnabled {
                    for result in top where result.confidence >= 0.2 {
                        self.checkTriggers(label: result.label, confidence: result.confidence)
                    }
                }
            }
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        try? handler.perform([request])
    }

    private func checkTriggers(label: String, confidence: Float) {
        guard confidence >= 0.2 else { return }
        let blocking = BlockingManager.shared
        let active = blocking.activeProfile

        guard active.isActive,
              active.anchorObjects.contains(where: { VisionLabelCatalog.matches(stored: $0, detected: label) })
        else { return }

        let off = BlockProfile.off
        guard off.id != lastActivatedProfileID else { return }
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.lastActivatedProfileID = off.id
            Task { await BlockingManager.shared.activate(off) }
        }
    }
}
