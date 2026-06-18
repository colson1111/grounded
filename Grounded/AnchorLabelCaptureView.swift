import SwiftUI

/// Camera flow for choosing an anchor label: capture a frame, then pick from ranked detections.
struct AnchorLabelCaptureView: View {
    var onSelect: (String) -> Void

    @ObservedObject private var manager = ObjectRecognitionManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var capturedResults: [(label: String, confidence: Float)]?
    @State private var isCapturing = false
    @State private var showLabelBrowser = false

    var body: some View {
        ZStack {
            CameraPreviewView(session: manager.captureSession)
                .ignoresSafeArea()

            if capturedResults == nil {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.7), lineWidth: 2)
                    .padding(48)
                    .allowsHitTesting(false)
            }

            VStack {
                HStack {
                    Button("Done") {
                        manager.stopScanning()
                        dismiss()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.5), in: Capsule())
                    .foregroundStyle(.white)

                    Spacer()

                    if capturedResults != nil {
                        Button("Retake") { capturedResults = nil }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.5), in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                .padding()

                Spacer()

                bottomPanel
                    .padding()
            }
        }
        .onAppear { manager.startScanning(activationEnabled: false) }
        .onDisappear { manager.stopScanning() }
        .sheet(isPresented: $showLabelBrowser) {
            LabelBrowserView { selected in
                manager.stopScanning()
                onSelect(selected)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private var bottomPanel: some View {
        if let capturedResults {
            resultsPanel(capturedResults)
        } else {
            capturePrompt
        }
    }

    private var capturePrompt: some View {
        VStack(spacing: 12) {
            Text("Fill the box with your object — less background, more of the thing itself.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)

            Button {
                capture()
            } label: {
                Label(isCapturing ? "Capturing…" : "Capture", systemImage: "camera.shutter.button")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(GroundedTheme.calmGreen)
            .disabled(isCapturing)

            Button("Pick from label list instead") {
                showLabelBrowser = true
            }
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.85))
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
    }

    private func resultsPanel(_ results: [(label: String, confidence: Float)]) -> some View {
        let topConfidence = results.first?.confidence ?? 0

        return VStack(alignment: .leading, spacing: 10) {
            Text("Select a detected object")
                .font(.headline)
                .foregroundStyle(.white)

            if topConfidence < 0.15 {
                Text("Low confidence — move closer, add light, or pick from the label list.")
                    .font(.caption)
                    .foregroundStyle(GroundedTheme.warmEarth)
            }

            if results.isEmpty {
                Text("Nothing specific detected. Try filling the frame with the object, then retake.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(results.enumerated()), id: \.offset) { idx, result in
                            Button {
                                manager.stopScanning()
                                onSelect(result.label)
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(300))
                                    dismiss()
                                }
                            } label: {
                                HStack {
                                    Text(VisionLabelCatalog.displayName(result.label))
                                        .font(idx == 0 ? .body.bold() : .subheadline)
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Text(String(format: "%.0f%%", result.confidence * 100))
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            Button("Pick from label list instead") {
                showLabelBrowser = true
            }
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.85))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
    }

    private func capture() {
        guard !isCapturing else { return }
        isCapturing = true
        Task {
            let results = await manager.classifyLatestFrame(forAnchorCapture: true)
            await MainActor.run {
                capturedResults = results
                isCapturing = false
            }
        }
    }
}
