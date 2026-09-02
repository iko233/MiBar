import AppKit
import SwiftUI

/// 捕获 macOS 鼠标滚轮和触控板滑动手势的 NSViewRepresentable
struct ScrollWheelListener: NSViewRepresentable {
    var isEnabled: Bool = true
    var onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollWheelCatcherView {
        let view = ScrollWheelCatcherView()
        view.isEnabled = isEnabled
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollWheelCatcherView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.onScroll = onScroll
    }
}

final class ScrollWheelCatcherView: NSView {
    var isEnabled: Bool = true
    var onScroll: ((CGFloat) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .mouseMoved,
            .activeInActiveApp,
            .inVisibleRect
        ]
        let newArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(newArea)
        self.trackingArea = newArea
    }

    override func scrollWheel(with event: NSEvent) {
        guard isEnabled else {
            super.scrollWheel(with: event)
            return
        }

        let deltaY = event.scrollingDeltaY
        let deltaX = event.scrollingDeltaX
        let isPrecise = event.hasPreciseScrollingDeltas

        let delta: CGFloat
        if abs(deltaX) > abs(deltaY) {
            delta = isPrecise ? deltaX : (event.deltaX * 3.0)
        } else {
            delta = isPrecise ? deltaY : (event.deltaY * 3.0)
        }

        if abs(delta) > 0.001 {
            onScroll?(delta)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

/// macOS 27 Control Center 风格的高对比度流体交互滑块，支持拖拽、点击与鼠标滚轮/触控板调节。
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
    @State private var isHovered: Bool = false
    @State private var dragOffsetRatio: Double? = nil
    @State private var scrollAccumulator: Double = 0

    private var normalizedRatio: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        let currentVal = dragOffsetRatio ?? ((value - range.lowerBound) / span)
        return min(max(currentVal, 0.0), 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // 头部标题与数值
            HStack(alignment: .firstTextBaseline) {
                Label {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                } icon: {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isHovered ? .primary : .secondary)
                }
                .foregroundStyle(.primary)

                Spacer()

                Text(valueText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
            }

            // 胶囊滑块主体
            GeometryReader { geometry in
                let width = max(geometry.size.width, 1)
                let height: CGFloat = 28
                let ratio = normalizedRatio
                let fillWidth = max(0, width * ratio)

                ZStack(alignment: .leading) {
                    // 底层轨道背景
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                        .fill(trackBackground)
                        .overlay {
                            RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                                .strokeBorder(
                                    isHovered ? Color.primary.opacity(0.18) : Color.primary.opacity(0.08),
                                    lineWidth: 0.8
                                )
                        }

                    // 进度填充层（跟随胶囊形状裁剪）
                    Rectangle()
                        .fill(fillGradient)
                        .frame(width: fillWidth)
                        .clipShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous))

                    // 游标 Thumb 与发光指示
                    if ratio > 0.02 {
                        Capsule(style: .continuous)
                            .fill(.white)
                            .shadow(color: .black.opacity(0.26), radius: 2, x: 0, y: 1)
                            .frame(width: isDragging ? 5 : 3.5, height: height - 10)
                            .position(
                                x: min(max(fillWidth, height / 2), width - height / 4),
                                y: height / 2
                            )
                            .animation(.spring(response: 0.18, dampingFraction: 0.8), value: isDragging)
                    }
                }
                .frame(height: height)
                .contentShape(Rectangle())
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.14)) {
                        isHovered = hovering
                    }
                }
                .background {
                    ScrollWheelListener(isEnabled: isEnabled) { delta in
                        handleScroll(delta: delta)
                    }
                }
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
                            if value != clampedValue {
                                value = clampedValue
                                onChanged(clampedValue)
                            }
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

    /// 处理鼠标滚轮与触控板双指滚动手势
    private func handleScroll(delta: CGFloat) {
        guard isEnabled else { return }
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return }

        // 依据范围跨度自适应滚轮灵敏度（例如亮度跨度 99，色温跨度 3800）
        let sensitivity = max(span / 120.0, step)
        let rawChange = Double(delta) * sensitivity
        scrollAccumulator += rawChange

        let effectiveStep = max(step, 1.0)
        if abs(scrollAccumulator) >= effectiveStep {
            let stepsToTake = (scrollAccumulator / effectiveStep).rounded(.towardZero)
            let actualDelta = stepsToTake * effectiveStep
            scrollAccumulator -= actualDelta

            var targetValue = value + actualDelta
            if step > 0 {
                targetValue = (targetValue / step).rounded() * step
            }
            let clamped = min(max(targetValue, range.lowerBound), range.upperBound)
            if clamped != value {
                value = clamped
                onChanged(clamped)
            }
        }
    }
}

extension LightControlCapsuleSlider {
    /// 亮度滑块样式
    static func brightness(
        value: Binding<Double>,
        systemImage: String = "sun.max.fill",
        isEnabled: Bool,
        onChanged: @escaping (Double) -> Void
    ) -> LightControlCapsuleSlider {
        LightControlCapsuleSlider(
            title: "亮度",
            systemImage: systemImage,
            valueText: "\(Int(value.wrappedValue.rounded()))%",
            value: value,
            range: 1...100,
            step: 1,
            trackBackground: AnyShapeStyle(Color.primary.opacity(0.08)),
            fillGradient: LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.82, blue: 0.28),
                    Color(red: 1.0, green: 0.58, blue: 0.0)
                ],
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
            valueText: "\(Int(value.wrappedValue.rounded())) K",
            value: value,
            range: 2_700...6_500,
            step: 50,
            trackBackground: AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.58, blue: 0.20),
                        Color(red: 1.0, green: 0.78, blue: 0.45),
                        Color(red: 0.98, green: 0.96, blue: 0.92),
                        Color(red: 0.78, green: 0.88, blue: 1.0),
                        Color(red: 0.55, green: 0.75, blue: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            ),
            fillGradient: LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.58, blue: 0.20),
                    Color(red: 1.0, green: 0.78, blue: 0.45),
                    Color(red: 0.92, green: 0.95, blue: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            ),
            isEnabled: isEnabled,
            onChanged: onChanged
        )
    }
}
