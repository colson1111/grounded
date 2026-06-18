import SwiftUI
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

/// Reusable QR code section — embed inside any profile detail or editor view.
struct QRCodeSectionView: View {
    let profile: BlockProfile
    var printTitle: String?

    @State private var qrImage: UIImage?
    @State private var isGenerating = true

    private var payload: String { "grounded://profile/\(profile.id)" }
    private var titleForPrint: String { printTitle ?? profile.name }

    var body: some View {
        VStack(spacing: 12) {
            if isGenerating {
                generatingView
            } else if let image = qrImage {
                qrContent(image: image)
            } else {
                Text("Could not generate QR code.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: payload) {
            await generateQRCode()
        }
    }

    private var generatingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Generating QR code…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
    }

    @ViewBuilder
    private func qrContent(image: UIImage) -> some View {
        let shareItem = QRPrintDocument(
            qrImage: image,
            title: titleForPrint,
            subtitle: payload
        )
        let preview = SharePreview("Profile QR", image: Image(uiImage: image))

        ShareLink(item: shareItem, preview: preview) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 200)
        }

        ShareLink(item: shareItem, preview: preview) {
            Label("Share / Print", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.bordered)

        Text(payload)
            .font(.caption2)
            .foregroundStyle(.secondary)

        Text("Prints as one letter-size page with the QR centered (~3″).")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    private func generateQRCode() async {
        isGenerating = true
        qrImage = nil

        let payload = payload
        let image = await Task.detached(priority: .userInitiated) {
            QRCodeRenderer.image(for: payload, pointSize: 200)
        }.value

        qrImage = image
        isGenerating = false
    }
}

// MARK: - QR rendering

private enum QRCodeRenderer {
    private static let ciContext = CIContext()

    static func image(for string: String, pointSize: CGFloat) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = pointSize / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = ciContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Print layout

private enum QRPrintLayout {
    static let pageSize = CGSize(width: 612, height: 792) // US Letter @ 72 pt/in
    static let qrSize: CGFloat = 216 // 3 inches

    static func pdfData(qrImage: UIImage, title: String, subtitle: String) -> Data {
        let pageRect = CGRect(origin: .zero, size: pageSize)
        let pdfData = NSMutableData()
        UIGraphicsBeginPDFContextToData(pdfData, pageRect, nil)
        UIGraphicsBeginPDFPage()

        UIColor.white.setFill()
        UIRectFill(pageRect)

        let qrRect = CGRect(
            x: (pageSize.width - qrSize) / 2,
            y: (pageSize.height - qrSize) / 2 - 24,
            width: qrSize,
            height: qrSize
        )
        qrImage.draw(in: qrRect)

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 18),
            .foregroundColor: UIColor.black
        ]
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor.darkGray
        ]

        let titleSize = title.size(withAttributes: titleAttrs)
        title.draw(
            at: CGPoint(x: (pageSize.width - titleSize.width) / 2, y: qrRect.maxY + 28),
            withAttributes: titleAttrs
        )

        let subtitleSize = subtitle.size(withAttributes: subtitleAttrs)
        subtitle.draw(
            at: CGPoint(x: (pageSize.width - subtitleSize.width) / 2, y: qrRect.maxY + 54),
            withAttributes: subtitleAttrs
        )

        UIGraphicsEndPDFContext()
        return pdfData as Data
    }
}

private struct QRPrintDocument: Transferable {
    let qrImage: UIImage
    let title: String
    let subtitle: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { document in
            QRPrintLayout.pdfData(
                qrImage: document.qrImage,
                title: document.title,
                subtitle: document.subtitle
            )
        }
    }
}
