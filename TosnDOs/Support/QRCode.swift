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

#if os(macOS)
import AppKit

extension QRCode {
    /// Reads a QR out of an image the user dropped or pasted. Core Image does
    /// the decoding on-device; no camera, no extra permission, no new framework.
    static func message(in data: Data) -> String? {
        // ImageIO covers png / jpeg / heic / webp — the formats a screenshot or a
        // photo of a screen arrives in after passing through a chat app.
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        if let text = detect(image) { return text }

        // A photo of a screen is often soft or small; one 2x pass fixes most of them.
        let ciImage = CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: 2, y: 2))
        if let scaled = CIContext().createCGImage(ciImage, from: ciImage.extent) {
            return detect(scaled)
        }
        return nil
    }

    private static func detect(_ image: CGImage) -> String? {
        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
        let features = detector?.features(in: CIImage(cgImage: image)) as? [CIQRCodeFeature]
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
