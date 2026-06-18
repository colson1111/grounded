import SwiftUI
import AVFoundation

struct ObjectRecognitionView: View {
    private struct DetectionPopup {
        let title: String
        let message: String
        let tint: Color
    }

    @ObservedObject private var manager = ObjectRecognitionManager.shared
    @Environment(\.dismiss) private var dismiss

    /// When set, the view runs in test mode: detected labels are shown but profiles are not
    /// activated. Tapping "Add" calls this closure with the detected label.
    var onAddTrigger: ((String) -> Void)? = nil
    var onDetection: ((String) -> Void)? = nil
    var showsDismissControl = true
    /// After anchor scan, activate this profile instead of unlocking to Off.
    var switchToProfile: BlockProfile? = nil
    /// When true, a matching anchor dismisses without changing the active profile.
    var verifyAnchorOnly: Bool = false
    var onAnchorVerified: (() -> Void)? = nil

    private var isTestMode: Bool { onAddTrigger != nil }
    @State private var hasHandledDetection = false
    @State private var detectionPopup: DetectionPopup?

    var body: some View {
        ZStack {
            CameraPreviewView(session: manager.captureSession)
                .ignoresSafeArea()

            VStack {
                HStack {
                    if showsDismissControl {
                        Button("Done") {
                            manager.stopScanning()
                            dismiss()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.5), in: Capsule())
                        .foregroundStyle(.white)
                    }

                    Spacer()

                    if isTestMode {
                        Text("Test Mode")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(GroundedTheme.warmEarth.opacity(0.9), in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                .padding()

                Spacer()

                detectionOverlay
                    .padding()
            }

            if let detectionPopup {
                detectionPopupOverlay(detectionPopup)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: detectionPopup != nil)
        .onAppear { manager.startScanning(activationEnabled: false) }
        .onDisappear { manager.stopScanning() }
        .onReceive(manager.$topResults) { _ in
            handleAnchorDetectionIfNeeded()
        }
    }

    private var detectionOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            if manager.topResults.isEmpty {
                Text("Point camera at an object...")
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                if !isTestMode {
                    statusLabel
                }

                ForEach(Array(manager.topResults.enumerated()), id: \.offset) { idx, result in
                    HStack {
                        Text(VisionLabelCatalog.displayName(result.label))
                            .font(idx == 0 ? .body.bold() : .subheadline)
                            .foregroundStyle(idx == 0 ? .white : .white.opacity(0.7))
                        Spacer()
                        Text(String(format: "%.0f%%", result.confidence * 100))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                        if isTestMode {
                            Button("Add") {
                                onAddTrigger?(result.label)
                                manager.stopScanning()
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(GroundedTheme.calmGreen)
                            .foregroundStyle(.white)
                            .font(.caption)
                            .controlSize(.mini)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
    }

    private func detectionPopupOverlay(_ popup: DetectionPopup) -> some View {
        VStack(spacing: 12) {
            GroundedAnchorIcon(size: 42, color: popup.tint)

            Text(popup.title)
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text(popup.message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(24)
        .frame(maxWidth: 320)
        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 22))
        .padding()
    }

    @ViewBuilder
    private var statusLabel: some View {
        let active = BlockingManager.shared.activeProfile
        if active.isActive, isAnchorDetected {
            Text(switchToProfile == nil ? "Anchor found — unlocking" : "Anchor found — switching")
                .font(.caption.bold())
                .foregroundStyle(GroundedTheme.calmGreen)
        }
    }

    private var isAnchorDetected: Bool {
        let active = BlockingManager.shared.activeProfile
        guard active.isActive else { return false }
        return manager.topResults.contains(where: { result in
            active.anchorObjects.contains(where: { VisionLabelCatalog.matches(stored: $0, detected: result.label) })
        })
    }

    private func handleAnchorDetectionIfNeeded() {
        guard !isTestMode, !hasHandledDetection else { return }

        let threshold: Float = 0.2
        let filtered = manager.topResults.filter { $0.confidence >= threshold }
        guard !filtered.isEmpty else { return }

        let activeProfile = BlockingManager.shared.activeProfile
        guard activeProfile.isActive else { return }

        guard let anchorLabel = filtered.first(where: { result in
            activeProfile.anchorObjects.contains(where: { VisionLabelCatalog.matches(stored: $0, detected: result.label) })
        })?.label else { return }

        hasHandledDetection = true
        manager.stopScanning()
        showAnchorDetected(label: anchorLabel, activeProfile: activeProfile)
    }

    private func showAnchorDetected(label: String, activeProfile: BlockProfile) {
        if verifyAnchorOnly {
            detectionPopup = DetectionPopup(
                title: "Anchor verified",
                message: "You can edit blocked apps.",
                tint: GroundedTheme.calmGreen
            )
            Task {
                try? await Task.sleep(nanoseconds: 700_000_000)
                await MainActor.run {
                    onAnchorVerified?()
                    dismiss()
                }
            }
            return
        }

        let destination = switchToProfile
        detectionPopup = DetectionPopup(
            title: "Anchor found: \(VisionLabelCatalog.displayName(label))",
            message: destination == nil
                ? "Unlocking \(activeProfile.name). The camera will close in a moment."
                : "Switching to \(destination!.name). The camera will close in a moment.",
            tint: GroundedTheme.calmGreen
        )

        Task {
            let target = destination ?? BlockProfile.off
            await BlockingManager.shared.activate(target)
            onDetection?(destination?.name ?? activeProfile.name)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { dismiss() }
        }
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        PreviewUIView(session: session)
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    init(session: AVCaptureSession) {
        super.init(frame: .zero)
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) { fatalError() }
}
