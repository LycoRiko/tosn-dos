import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
#if os(iOS)
import UIKit
import Photos
#endif

/// Draws the share code as a QR image. Generated locally; nothing leaves the device.
enum QRCode {
    /// `CGImage` so the same drawing code serves both platforms.
    static func image(for text: String, scale: CGFloat = 10) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }

    /// The camera only offers "open in app" for URLs, so the QR carries the
    /// deep link rather than the bare code. Scanning it needs no scanner of ours.
    static func link(for code: String) -> String {
        var components = URLComponents()
        components.scheme = "tosndos"
        components.host = "import"
        components.queryItems = [URLQueryItem(name: "c", value: code)]
        return components.string ?? "tosndos://import?c=\(code)"
    }

    #if os(iOS)
    /// Add-only permission: the app never reads the library. Pass `ask: false`
    /// to save silently when permission is already there and skip otherwise —
    /// a permission prompt the user never asked for is worse than a button.
    static func saveToPhotos(_ image: UIImage, ask: Bool) async -> Bool {
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined, ask {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard status == .authorized || status == .limited else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            return true
        } catch {
            return false
        }
    }
    #endif
}

/// Preview the code and hand it to the share sheet. On iOS it also offers to
/// keep a copy in Photos.
struct QRSheet: View {
    var title: String
    var code: String

    @Environment(\.dismiss) private var dismiss
    @State private var saved = false
    @State private var saveFailed = false

    private var qr: CGImage? {
        QRCode.image(for: QRCode.link(for: code))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let qr {
                    Image(decorative: qr, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 240)
                        .padding(16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .accessibilityLabel(Text("QR code for \(title)"))

                    ShareLink(item: Image(decorative: qr, scale: 1), preview: SharePreview(title)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.medium))
                    }
                }

                Text(title)
                    .font(.headline)

                Text("Scan this with the Camera app to import the list.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                #if os(iOS)
                if saved {
                    Label("Saved to Photos", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(Theme.mint)
                } else if let qr, !saveFailed {
                    Button {
                        Task {
                            saved = await QRCode.saveToPhotos(UIImage(cgImage: qr), ask: true)
                            saveFailed = !saved
                        }
                    } label: {
                        Label("Save to Photos", systemImage: "photo.badge.plus")
                            .font(.subheadline.weight(.medium))
                    }
                } else if saveFailed {
                    Text("Could not save to Photos. Check the permission in Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                #endif
            }
            .padding(24)
            .navigationTitle("Scan to import")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #if os(iOS)
            .task {
                guard let qr, PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized else { return }
                saved = await QRCode.saveToPhotos(UIImage(cgImage: qr), ask: false)
            }
            #endif
        }
    }
}

#if os(macOS)
import AppKit

extension QRCode {
    /// Reads a QR out of an image the user dropped or pasted. Core Image does
    /// the decoding on-device; no camera, no extra permission, no new framework.
    static func message(in data: Data) -> String? {
        guard
            let image = NSImage(data: data),
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }

        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
        let features = detector?.features(in: CIImage(cgImage: cgImage)) as? [CIQRCodeFeature]
        return features?.first?.messageString
    }

    /// Accepts either the deep link or the bare code that older images carry.
    static func code(from message: String) -> String? {
        if let components = URLComponents(string: message),
           let value = components.queryItems?.first(where: { $0.name == "c" })?.value {
            return value
        }
        return message.hasPrefix(ListCodec.prefix) ? message : nil
    }
}
#endif
