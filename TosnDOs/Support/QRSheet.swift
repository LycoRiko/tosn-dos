import SwiftUI
#if os(iOS)
import Photos
import UIKit
#endif

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
