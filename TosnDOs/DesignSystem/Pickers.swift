import SwiftUI

/// Shared symbol + color picker for lists and templates.
/// Both editors use it so the two surfaces always offer the same choices.
struct IconColorPicker: View {
    @Binding var symbol: String
    @Binding var colorHex: Int

    private let columns = [GridItem(.adaptive(minimum: 42), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(ListSymbols.all, id: \.self) { name in
                    Button {
                        symbol = name
                    } label: {
                        Image(systemName: name)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(symbol == name ? Color.white : Color.primary.opacity(0.72))
                            .frame(width: 38, height: 38)
                            .background(
                                symbol == name
                                    ? AnyShapeStyle(ListPalette.color(colorHex))
                                    : AnyShapeStyle(Color.primary.opacity(0.06)),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(name))
                    .accessibilityAddTraits(symbol == name ? .isSelected : [])
                }
            }

            HStack(spacing: 11) {
                ForEach(ListPalette.colors, id: \.self) { hex in
                    Button {
                        colorHex = hex
                    } label: {
                        Circle()
                            .fill(ListPalette.color(hex))
                            .frame(width: 24, height: 24)
                            .overlay {
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.95), lineWidth: colorHex == hex ? 2 : 0)
                                    .padding(2)
                            }
                            .overlay {
                                Circle().strokeBorder(ListPalette.color(hex).opacity(0.22), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Color"))
                    .accessibilityAddTraits(colorHex == hex ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 4)
    }
}
