import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

/// Where a page's backdrop comes from.
struct BackgroundSetting: Equatable {
    var imageName: String = ""
    var blur: Double = 24
    var opacity: Double = 0.92

    var hasImage: Bool { !imageName.isEmpty }

    static let plain = BackgroundSetting()

    init(imageName: String = "", blur: Double = 24, opacity: Double = 0.92) {
        self.imageName = imageName
        self.blur = blur
        self.opacity = opacity
    }
}

/// Stores user-chosen backdrop images on disk and hands them back as `Image`.
///
/// Images are downsampled on import (long edge capped) and encoded as JPEG, so
/// a library of backdrops costs a few hundred kilobytes instead of tens of
/// megabytes.
enum BackgroundStore {
    static let folderName = "Backgrounds"
    static let maxPixelSize = 2048

    static var directory: URL {
        let base = SharedStore.sharedDirectory ?? URL.applicationSupportDirectory
        let url = base.appending(path: folderName, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func url(for name: String) -> URL {
        directory.appending(path: name)
    }

    /// Imports raw image data and returns the generated file name, or nil when
    /// the data cannot be decoded.
    static func importImage(_ data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let name = "bg-\(UUID().uuidString).jpg"
        let destinationURL = url(for: name)
        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }

        CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return name
    }

    static func image(named name: String) -> Image? {
        guard !name.isEmpty,
              let source = CGImageSourceCreateWithURL(url(for: name) as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return Image(decorative: cgImage, scale: 1, orientation: .up)
    }

    static func delete(_ name: String) {
        guard !name.isEmpty else { return }
        try? FileManager.default.removeItem(at: url(for: name))
    }
}

/// UserDefaults keys for the global backdrop.
enum BackgroundKey {
    static let imageName = "bg.imageName"
    static let blur = "bg.blur"
    static let opacity = "bg.opacity"
}

extension TodoList {
    /// Per-list backdrop. Falls back to the global one when no photo is set.
    var backgroundSetting: BackgroundSetting {
        BackgroundSetting(
            imageName: backgroundImageName,
            blur: backgroundBlur,
            opacity: backgroundOpacity
        )
    }

    func applyBackground(_ setting: BackgroundSetting) {
        backgroundImageName = setting.imageName
        backgroundBlur = setting.blur
        backgroundOpacity = setting.opacity
    }
}
