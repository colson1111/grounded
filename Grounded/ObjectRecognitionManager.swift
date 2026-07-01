import Foundation
import AVFoundation
import CoreImage
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

    // Frame-skip so CLIP (slower than VNClassify) doesn't back up the queue
    private var frameCounter = 0
    private let classifyEveryNFrames = 3

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

    /// Anchor setup: classify latest frame, returning top CLIP matches.
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

                let topK = forAnchorCapture ? 20 : 10
                let results = CLIPClassifier.shared.classify(pixelBuffer: pixelBuffer, topK: topK)
                    .map { (label: $0.id, confidence: $0.similarity) }
                continuation.resume(returning: results)
            }
        }
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

        // Run CLIP every N frames to avoid queue saturation
        frameCounter += 1
        guard frameCounter % classifyEveryNFrames == 0 else { return }

        let results = CLIPClassifier.shared.classify(pixelBuffer: pixelBuffer, topK: 10)
        let top = results.map { (label: $0.id, confidence: $0.similarity) }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.topResults = top
            if self.activationEnabled {
                for result in top {
                    self.checkTriggers(label: result.label, confidence: result.confidence)
                }
            }
        }
    }

    private func checkTriggers(label: String, confidence: Float) {
        let blocking = BlockingManager.shared
        let active = blocking.activeProfile

        guard active.isActive,
              active.anchorObjects.contains(where: { $0 == label })
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
