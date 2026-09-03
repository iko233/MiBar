import SwiftUI

// MARK: - Scene Glass Button

/// 具有 macOS 毛玻璃质感与反光描边的快捷场景胶囊按钮
struct SceneGlassButton: View {
    let preset: LightPresetItem
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: preset.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(
                        isSelected
                            ? preset.accentColor
                            : (isHovered ? Color.primary : Color.secondary)
                    )

                Text(preset.title)
                    .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .foregroundStyle(
                        isSelected
                            ? Color.primary
                            : (isHovered ? Color.primary : Color.secondary)
                    )
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            .background {
                // 毛玻璃底层材质与色彩浸润
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(
                                isSelected
                                    ? preset.accentColor.opacity(0.18)
                                    : (isHovered ? Color.primary.opacity(0.08) : Color.primary.opacity(0.035))
                            )
                    }
                    .overlay {
                        // 顶部玻璃高光反光 (Specular highlight)
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isSelected ? 0.28 : (isHovered ? 0.22 : 0.10)),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
            }
            .overlay {
                // 玻璃高光反光描边
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: isSelected
                                ? [
                                    preset.accentColor.opacity(0.65),
                                    preset.accentColor.opacity(0.25)
                                ]
                                : [
                                    Color.primary.opacity(isHovered ? 0.24 : 0.12),
                                    Color.primary.opacity(isHovered ? 0.10 : 0.04)
                                ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isSelected ? 1.0 : 0.8
                    )
            }
            .contentShape(Capsule(style: .continuous))
            .scaleEffect(isHovered && isEnabled ? 1.02 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isHovered)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering in
            if isEnabled {
                isHovered = hovering
            }
        }
        .help("\(preset.title) · \(preset.subtitle)")
    }
}

// MARK: - Light Menu Presets Section

/// 场景预设列表区块
struct LightMenuPresetsSection: View {
    let store: LightStore

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("场景")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.primary)

            HStack(spacing: 6) {
                ForEach(LightPresetItem.allPresets) { preset in
                    let isSelected =
                        store.state.isOn
                        && abs(store.state.brightness - preset.brightness) <= 5
                        && abs(store.state.colorTemperature - preset.colorTemperature) <= 150

                    SceneGlassButton(
                        preset: preset,
                        isSelected: isSelected,
                        isEnabled: store.state.isOn
                    ) {
                        store.applyPreset(
                            colorTemperature: preset.colorTemperature,
                            brightness: preset.brightness
                        )
                    }
                }
            }
        }
        .opacity(store.state.isOn ? 1 : 0.55)
    }
}
