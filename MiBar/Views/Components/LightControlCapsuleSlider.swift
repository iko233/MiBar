import SwiftUI

/// macOS 27 Control Center 风格的高对比度流体交互滑块。
struct LightControlCapsuleSlider: View {
    let title: String
    let systemImage: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let trackBackground: AnyShapeStyle
    let fillGradient: LinearGradient
    var isEnabled: Bool = true
    let onChanged: (Double) -> Void

    @State private var isDragging: Bool = false
    @State private var dragOffsetRatio: Double? = nil

    private var normalizedRatio: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        let currentVal = dragOffsetRatio ?? ((value - range.lowerBound) / span)
        return min(max(currentVal, 0.0), 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                Text(valueText)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
            }

            GeometryReader { geometry in
                let width = max(geometry.size.width, 1)
                let fillWidth = width * normalizedRatio
                let height: CGFloat = 28

                ZStack(alignment: .leading) {
                    // 底层轨道
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                        .fill(trackBackground)
                        .overlay {
                            RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8)
                        }

                    // 填充进度
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                        .fill(fillGradient)
                        .frame(width: max(fillWidth, height))
                        .clipShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous))

                    // 流体指示游标 Thumb
                    if fillWidth > 8 {
                        Capsule(style: .continuous)
                            .fill(.white)
                            .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                            .frame(width: 4, height: height - 10)
                            .position(
                                x: min(max(fillWidth, height / 2), width - 4),
                                y: height / 2
                            )
                    }
                }
                .frame(height: height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            guard isEnabled else { return }
                            isDragging = true
                            let progress = min(max(gesture.location.x / width, 0.0), 1.0)
                            dragOffsetRatio = progress
                            let span = range.upperBound - range.lowerBound
                            var rawValue = range.lowerBound + progress * span
                            if step > 0 {
                                rawValue = (rawValue / step).rounded() * step
                            }
                            let clampedValue = min(max(rawValue, range.lowerBound), range.upperBound)
                            value = clampedValue
                            onChanged(clampedValue)
                        }
                        .onEnded { _ in
                            isDragging = false
                            dragOffsetRatio = nil
                        }
                )
            }
            .frame(height: 28)
            .opacity(isEnabled ? 1.0 : 0.45)
            .animation(.easeInOut(duration: 0.18), value: isEnabled)
        }
    }
}

extension LightControlCapsuleSlider {
    /// 亮度滑块样式
    static func brightness(
        value: Binding<Double>,
        isEnabled: Bool,
        onChanged: @escaping (Double) -> Void
    ) -> LightControlCapsuleSlider {
        LightControlCapsuleSlider(
            title: "亮度",
            systemImage: "sun.max.fill",
            valueText: "\(Int(value.wrappedValue))%",
            value: value,
            range: 1...100,
            step: 1,
            trackBackground: AnyShapeStyle(Color.primary.opacity(0.08)),
            fillGradient: LinearGradient(
                colors: [Color.yellow.opacity(0.85), Color.orange],
                startPoint: .leading,
                endPoint: .trailing
            ),
            isEnabled: isEnabled,
            onChanged: onChanged
        )
    }

    /// 色温滑块样式 (2700K ~ 6500K 全光谱带)
    static func colorTemperature(
        value: Binding<Double>,
        isEnabled: Bool,
        onChanged: @escaping (Double) -> Void
    ) -> LightControlCapsuleSlider {
        LightControlCapsuleSlider(
            title: "色温",
            systemImage: "thermometer.sun.fill",
            valueText: "\(Int(value.wrappedValue))K",
            value: value,
            range: 2_700...6_500,
            step: 50,
            trackBackground: AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.58, blue: 0.20),
                        Color(red: 1.0, green: 0.80, blue: 0.50),
                        Color(red: 0.98, green: 0.95, blue: 0.90),
                        Color(red: 0.80, green: 0.90, blue: 1.0),
                        Color(red: 0.60, green: 0.80, blue: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            ),
            fillGradient: LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.58, blue: 0.20),
                    Color(red: 1.0, green: 0.80, blue: 0.50),
                    Color(red: 0.85, green: 0.92, blue: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            ),
            isEnabled: isEnabled,
            onChanged: onChanged
        )
    }
}
