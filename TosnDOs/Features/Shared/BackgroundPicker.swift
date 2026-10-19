import SwiftUI
import PhotosUI

/// Photo backdrop controls, shared by the global settings screen and the
/// per-list editor so both behave identically.
struct BackgroundPicker: View {
    @Binding var setting: BackgroundSetting

    @State private var pickerItem: PhotosPickerItem?
    @State private var isLoading = false

    private var preview: Image? {
        BackgroundStore.image(named: setting.imageName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let preview {
                preview
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 118)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if isLoading {
                            ProgressView()
                                .padding(8)
                        }
                    }
                    .accessibilityLabel(Text("Background preview"))
            }

            HStack(spacing: 14) {
                PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                    Label(
                        setting.hasImage ? "Change photo" : "Choose photo",
                        systemImage: "photo.on.rectangle"
                    )
                    .font(.subheadline.weight(.medium))
                }

                Spacer(minLength: 0)

                if setting.hasImage {
                    Button(role: .destructive) {
                        BackgroundStore.delete(setting.imageName)
                        setting = .plain
                    } label: {
                        Text("Remove")
                            .font(.subheadline)
                    }
                }
            }

            if setting.hasImage {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Blur")
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(setting.blur))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $setting.blur, in: 0...60, step: 1)
                        .tint(Theme.accent)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: setting.hasImage)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: setting.imageName)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            load(item)
        }
    }

    private func load(_ item: PhotosPickerItem) {
        isLoading = true
        Task {
            defer { isLoading = false }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let name = BackgroundStore.importImage(data) else { return }

            let previous = setting.imageName
            withAnimation(.easeInOut(duration: 0.2)) {
                setting.imageName = name
            }
            if !previous.isEmpty {
                BackgroundStore.delete(previous)
            }
            pickerItem = nil
        }
    }
}
