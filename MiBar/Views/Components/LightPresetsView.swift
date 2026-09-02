import SwiftUI

/// 单个灯光场景预设模型
struct LightPresetItem: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let colorTemperature: Int
    let brightness: Int
    let accentColor: Color

    static let allPresets: [LightPresetItem] = [
        LightPresetItem(
            id: "night",
            title: "夜间",
            subtitle: "3000K · 10%",
            icon: "moon.stars.fill",
            colorTemperature: 3000,
            brightness: 10,
            accentColor: .indigo
        ),
        LightPresetItem(
            id: "relax",
            title: "休闲",
            subtitle: "2700K · 40%",
            icon: "cup.and.saucer.fill",
            colorTemperature: 2700,
            brightness: 40,
            accentColor: .orange
        ),
        LightPresetItem(
            id: "read",
            title: "阅读",
            subtitle: "4000K · 80%",
            icon: "book.fill",
            colorTemperature: 4000,
            brightness: 80,
            accentColor: .yellow
        ),
        LightPresetItem(
            id: "work",
            title: "专注",
            subtitle: "5000K · 100%",
            icon: "laptopcomputer",
            colorTemperature: 5000,
            brightness: 100,
            accentColor: .cyan
        )
    ]
}

/// macOS 27 Control Center 风格的快捷场景卡片矩阵
struct LightPresetsView: View {
    let currentBrightness: Int
    let currentColorTemperature: Int
    let isLightOn: Bool
    let onSelectPreset: (LightPresetItem) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("快捷场景")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(LightPresetItem.allPresets) { preset in
                    let isCurrent = isLightOn
                        && abs(currentBrightness - preset.brightness) <= 5
                        && abs(currentColorTemperature - preset.colorTemperature) <= 150

                    Button {
                        onSelectPreset(preset)
                    } label: {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(isCurrent ? preset.accentColor : Color.primary.opacity(0.08))
                                    .frame(width: 28, height: 28)
                                Image(systemName: preset.icon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(isCurrent ? .white : preset.accentColor)
                            }

                            VStack(alignment: .leading, spacing: 1) {
                                Text(preset.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text(preset.subtitle)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isCurrent ? preset.accentColor.opacity(0.16) : Color.primary.opacity(0.04))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    isCurrent ? preset.accentColor.opacity(0.5) : Color.primary.opacity(0.06),
                                    lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }
}
