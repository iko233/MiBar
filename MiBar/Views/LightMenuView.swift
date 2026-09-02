import AppKit
import SwiftUI

/// 挂灯菜单栏主视图：协调主控制、配置页以及弹窗浮层。
struct LightMenuView: View {
    @Bindable var store: LightStore
    @State private var isConfirmingClearConfiguration = false
    @State private var isShowingAbout = false

    /// 构建菜单栏弹窗：macOS 26+ 用系统原生毛玻璃窗口承载内容。
    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                menuBase
                    .containerBackground(.clear, for: .window)
            } else {
                menuBase
            }
        }
        .task {
            await store.start()
        }
    }

    /// 紧凑原生菜单基底，支持自动根据内容收缩高度。
    private var menuBase: some View {
        VStack(spacing: 0) {
            if store.isEditingConfiguration {
                LightConfigurationView(
                    store: store,
                    isConfirmingClearConfiguration: $isConfirmingClearConfiguration
                )
            } else {
                mainControlView
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 15)
        .padding(.bottom, 10)
        .frame(width: MenuBarWindowSizing.menuWidth)
        .fixedSize(horizontal: false, vertical: true)
        .overlay {
            if isConfirmingClearConfiguration {
                MenuBarModal(
                    title: "删除本机配置",
                    message: "只清除这台 Mac 上的配置，不影响米家账号和挂灯本身。",
                    confirmTitle: "删除配置",
                    isDestructive: true,
                    onCancel: { isConfirmingClearConfiguration = false },
                    onConfirm: {
                        isConfirmingClearConfiguration = false
                        store.clearConfiguration()
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else if isShowingAbout {
                AboutModal(onDismiss: { isShowingAbout = false })
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: isConfirmingClearConfiguration)
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: isShowingAbout)
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: store.isEditingConfiguration)
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: store.state.isOn)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .overlay {
                        MenuBarWindowSizeSync(size: proxy.size)
                            .frame(width: 0, height: 0)
                    }
            }
        }
    }

    // MARK: - Main Control View

    /// 主控制视图
    private var mainControlView: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            LightMenuHeaderView(store: store)

            // MARK: - Main Brightness Control
            brightnessSection
                .padding(.top, 18)

            // MARK: - Color Temperature
            temperatureSection
                .padding(.top, 18)

            // MARK: - Scene Presets
            LightMenuPresetsSection(store: store)
                .padding(.top, 18)

            // MARK: - Footer
            LightMenuFooterView(
                store: store,
                isShowingAbout: $isShowingAbout
            )
            .padding(.top, 16)
        }
    }

    // MARK: - Brightness Section

    private var brightnessSection: some View {
        LightControlCapsuleSlider.brightness(
            value: Binding(
                get: {
                    Double(store.state.brightness)
                },
                set: {
                    store.scheduleBrightness(Int($0.rounded()))
                }
            ),
            systemImage: brightnessIcon,
            isEnabled: store.state.isOn,
            onChanged: { newValue in
                store.scheduleBrightness(Int(newValue.rounded()))
            }
        )
    }

    // MARK: - Temperature Section

    private var temperatureSection: some View {
        VStack(spacing: 6) {
            LightControlCapsuleSlider.colorTemperature(
                value: Binding(
                    get: {
                        Double(store.state.colorTemperature)
                    },
                    set: {
                        store.scheduleColorTemperature(
                            Int($0.rounded())
                        )
                    }
                ),
                isEnabled: store.state.isOn,
                onChanged: { newValue in
                    store.scheduleColorTemperature(
                        Int(newValue.rounded())
                    )
                }
            )

            HStack {
                Text("暖 2700K")
                Spacer()
                Text("中性 4000K")
                Spacer()
                Text("冷 6500K")
            }
            .font(.system(size: 9.5))
            .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Helpers

    private var brightnessIcon: String {
        switch store.state.brightness {
        case 0..<25:
            return "sun.min"
        case 25..<70:
            return "sun.max"
        default:
            return "sun.max.fill"
        }
    }
}
