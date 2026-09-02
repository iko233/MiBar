import AppKit
import SwiftUI

// MARK: - Menu Item Row

struct MenuItemRow: View {
    let title: String
    var icon: String? = nil
    var hasChevron: Bool = false
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(
                            .system(
                                size: 11.5,
                                weight: .medium
                            )
                        )
                        .foregroundStyle(
                            isDestructive
                                ? Color.red
                                : Color.secondary
                        )
                        .frame(width: 14, alignment: .leading)
                }

                Text(title)
                    .font(
                        .system(
                            size: 11.5,
                            weight: .regular
                        )
                    )

                Spacer()

                if hasChevron {
                    Image(systemName: "chevron.right")
                        .font(
                            .system(
                                size: 9,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(
                isDestructive
                    ? Color.red
                    : Color.primary
            )
            .padding(.horizontal, 0)
            .frame(height: 29)
            .background {
                RoundedRectangle(
                    cornerRadius: 6,
                    style: .continuous
                )
                .fill(
                    isHovered
                        ? Color.primary.opacity(0.07)
                        : Color.clear
                )
                .padding(.horizontal, -6)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Custom Button Styles (Height 36)

struct MiBarPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(configuration.isPressed ? 0.82 : 1.0),
                                Color.accentColor.opacity(configuration.isPressed ? 0.92 : 0.96)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Color.accentColor.opacity(configuration.isPressed ? 0.1 : 0.22), radius: 3, y: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.88 : 1.0) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct MiBarSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.primary)
            .frame(height: 36)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        configuration.isPressed
                            ? Color.primary.opacity(0.12)
                            : (isHovered ? Color.primary.opacity(0.08) : Color.primary.opacity(0.045))
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(isEnabled ? 1.0 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .onHover { isHovered = $0 }
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct MiBarDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.red)
            .frame(height: 36)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        configuration.isPressed
                            ? Color.red.opacity(0.18)
                            : (isHovered ? Color.red.opacity(0.12) : Color.red.opacity(0.06))
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.red.opacity(0.18), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(isEnabled ? 1.0 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .onHover { isHovered = $0 }
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}
