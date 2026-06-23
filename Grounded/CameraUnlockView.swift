import SwiftUI

/// Combined camera flow for unlocking: scan an anchor object or a QR code.
struct CameraUnlockView: View {
    /// When set, a successful anchor scan switches to this profile instead of unlocking fully.
    var switchToProfile: BlockProfile? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var mode: ScanMode = .object

    private enum ScanMode: String, CaseIterable, Identifiable {
        case object = "Object"
        case qr = "QR Code"
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            switch mode {
            case .object:
                ObjectRecognitionView(showsDismissControl: false, switchToProfile: switchToProfile)
            case .qr:
                QRScannerView { code in
                    handleUnlockQR(code)
                }
                .ignoresSafeArea()
            }

            VStack {
                HStack {
                    Button("Done") {
                        ObjectRecognitionManager.shared.stopScanning()
                        dismiss()
                    }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.5), in: Capsule())
                        .foregroundStyle(.white)

                    Spacer()

                    Picker("Scan mode", selection: $mode) {
                        ForEach(ScanMode.allCases) { scanMode in
                            Text(scanMode.rawValue).tag(scanMode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)
                }
                .padding()

                if let switchToProfile {
                    Text("Scan \(BlockingManager.shared.activeProfile.name)'s anchor or the master QR code to switch to \(switchToProfile.name)")
                        .font(.subheadline.bold())
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                        .padding(.horizontal)
                }

                Spacer()
            }
        }
    }

    private func handleUnlockQR(_ code: String) {
        guard code.hasPrefix("grounded://profile/") else { return }
        let profileID = String(code.dropFirst("grounded://profile/".count))
        guard profileID == "off" else { return }

        Task {
            if let target = switchToProfile {
                await BlockingManager.shared.activate(target)
            } else {
                await BlockingManager.shared.activate(BlockProfile.off)
            }
            dismiss()
        }
    }
}
