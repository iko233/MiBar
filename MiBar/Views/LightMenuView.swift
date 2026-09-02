import AppKit
import SwiftUI

struct LightMenuView: View {
    @Bindable var store: LightStore
    @State private var isConfirmingClearConfiguration = false
    @State private var isTokenVisible = false
    @State private var isBackHovered = false

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
                configurationView
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
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: isConfirmingClearConfiguration)
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
            headerSection

            // MARK: - Main brightness control
            brightnessSection
                .padding(.top, 18)

            // MARK: - Color temperature
            temperatureSection
                .padding(.top, 18)

            // MARK: - Presets
            presetSection
                .padding(.top, 18)

            // MARK: - Footer
            footerSection
                .padding(.top, 16)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("MiBar")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: 5) {
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 5, height: 5)

                    Text(
                        store.isConnected
                            ? "米家显示器挂灯 1S"
                            : store.statusText
                    )
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }

            Spacer()

            if store.isWorking {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 34)
            } else {
                Toggle(
                    "电源",
                    isOn: Binding(
                        get: {
                            store.state.isOn
                        },
                        set: { value in
                            Task {
                                await store.setPower(value)
                            }
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Brightness

    private var brightnessSection: some View {
        VStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.055))
                    .frame(width: 60, height: 60)

                Image(systemName: brightnessIcon)
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(
                        store.state.isOn
                            ? Color.primary
                            : Color.secondary
                    )
            }

            VStack(spacing: 1) {
                Text("\(store.state.brightness)%")
                    .font(
                        .system(
                            size: 26,
                            weight: .medium,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Text("亮度")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: {
                        Double(store.state.brightness)
                    },
                    set: {
                        store.scheduleBrightness(Int($0.rounded()))
                    }
                ),
                in: 1...100,
                step: 1
            )
            .controlSize(.small)
            .disabled(!store.state.isOn)
        }
        .opacity(store.state.isOn ? 1 : 0.45)
        .animation(
            .easeInOut(duration: 0.18),
            value: store.state.isOn
        )
    }

    // MARK: - Temperature

    private var temperatureSection: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("色温")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(store.state.colorTemperature) K")
                    .font(
                        .system(
                            size: 11,
                            weight: .medium
                        )
                    )
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            Slider(
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
                in: 2_700...6_500,
                step: 50
            )
            .controlSize(.small)
            .disabled(!store.state.isOn)

            HStack {
                Text("暖")
                Spacer()
                Text("中性")
                Spacer()
                Text("冷")
            }
            .font(.system(size: 9.5))
            .foregroundStyle(.tertiary)
        }
        .opacity(store.state.isOn ? 1 : 0.45)
    }

    // MARK: - Presets

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("场景")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.primary)

            HStack(spacing: 6) {
                ForEach(LightPresetItem.allPresets) { preset in
                    let isSelected =
                        store.state.isOn
                        && abs(
                            store.state.brightness
                                - preset.brightness
                        ) <= 5
                        && abs(
                            store.state.colorTemperature
                                - preset.colorTemperature
                        ) <= 150

                    Button {
                        store.applyPreset(
                            colorTemperature:
                                preset.colorTemperature,
                            brightness:
                                preset.brightness
                        )
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: preset.icon)
                                .font(
                                    .system(
                                        size: 10,
                                        weight: .semibold
                                    )
                                )

                            Text(preset.title)
                                .font(
                                    .system(
                                        size: 10.5,
                                        weight: .medium
                                    )
                                )
                                .lineLimit(1)
                        }
                        .foregroundStyle(
                            isSelected
                                ? Color.primary
                                : Color.secondary
                        )
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 28
                        )
                        .background {
                            Capsule()
                                .fill(
                                    isSelected
                                        ? Color.primary.opacity(0.12)
                                        : Color.primary.opacity(0.045)
                            )
                        }
                        .overlay {
                            if isSelected {
                                Capsule()
                                    .strokeBorder(
                                        Color.primary.opacity(0.07),
                                        lineWidth: 0.5
                                    )
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!store.state.isOn)
                    .help(
                        "\(preset.title) · \(preset.subtitle)"
                    )
                }
            }
        }
        .opacity(store.state.isOn ? 1 : 0.55)
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.25)
                .padding(.bottom, 7)

            MenuItemRow(
                title: "设置",
                icon: "gearshape",
                hasChevron: true
            ) {
                store.isEditingConfiguration = true
            }

            MenuItemRow(
                title: "刷新状态",
                icon: "arrow.clockwise"
            ) {
                Task {
                    await store.refresh()
                }
            }
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

    private var connectionColor: Color {
        store.isConnected ? .green : .secondary
    }

    // MARK: - Configuration View

    /// 设置视图（IP/Token 配置与扫码导入）
    private var configurationView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Button {
                    store.isEditingConfiguration = false
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("返回")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .frame(height: 36)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isBackHovered ? Color.primary.opacity(0.08) : Color.clear)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .onHover { isBackHovered = $0 }

                Spacer()

                Text("设备配置")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Color.clear
                    .frame(width: 50, height: 36)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("局域网直连参数")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)

                // IP 输入
                HStack(spacing: 8) {
                    Image(systemName: "network")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    TextField("挂灯 IPv4 地址 (例: 192.168.31.200)", text: $store.host)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))

                    if !store.host.isEmpty {
                        Button {
                            store.host = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("清空 IP")
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }

                // Token 输入
                HStack(spacing: 8) {
                    Image(systemName: "key.horizontal.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    if isTokenVisible {
                        TextField("32 位 Token (Hex)", text: $store.tokenHex)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                    } else {
                        SecureField("32 位 Token (Hex)", text: $store.tokenHex)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                    }

                    if !store.tokenHex.isEmpty {
                        Button {
                            isTokenVisible.toggle()
                        } label: {
                            Image(systemName: isTokenVisible ? "eye.slash.fill" : "eye.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(isTokenVisible ? "隐藏 Token" : "显示 Token")

                        Button {
                            store.tokenHex = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("清空 Token")
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            !store.tokenHex.isEmpty && store.tokenHex.count != 32
                                ? Color.orange.opacity(0.4)
                                : Color.primary.opacity(0.08),
                            lineWidth: 1
                        )
                }

                if !store.tokenHex.isEmpty && store.tokenHex.count != 32 {
                    HStack {
                        Spacer()
                        Text("Token 应为 32 位 Hex (当前 \(store.tokenHex.count)/32)")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }
                    .padding(.top, -2)
                }
            }

            // 保存与删除按钮
            HStack(spacing: 8) {
                Button {
                    Task { await store.saveConfiguration() }
                } label: {
                    HStack(spacing: 6) {
                        if store.isWorking {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        Text(store.isWorking ? "正在连接…" : "保存并连接")
                    }
                }
                .buttonStyle(MiBarPrimaryButtonStyle())
                .disabled(!store.isConfigured || store.isWorking)

                Button(role: .destructive) {
                    isConfirmingClearConfiguration = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(MiBarDestructiveButtonStyle())
                .disabled(store.host.isEmpty && store.tokenHex.isEmpty)
                .help("删除本机配置")
            }

            Divider()
                .opacity(0.25)
                .padding(.vertical, 2)

            cloudImportSection
        }
    }

    /// 小米二维码登录与云端发现
    @ViewBuilder
    private var cloudImportSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Label("米家扫码快速导入", systemImage: "qrcode")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                if store.isCloudLoginActive {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let imageData = store.qrImageData,
               let image = NSImage(data: imageData) {
                VStack(spacing: 6) {
                    HStack {
                        Spacer()
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: 130, height: 130)
                            .padding(8)
                            .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                        Spacer()
                    }

                    Text("请使用米家 App 扫码并确认登录")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
            }

            if !store.cloudLoginStatus.isEmpty {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: store.isCloudLoginActive ? "arrow.triangle.2.circlepath" : "info.circle")
                        .font(.system(size: 10.5))
                        .foregroundStyle(store.isCloudLoginActive ? Color.accentColor : Color.secondary)
                        .padding(.top, 1)

                    Text(store.cloudLoginStatus)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 1)
            }

            ForEach(store.cloudDevices) { device in
                Button {
                    Task { await store.importCloudDevice(device) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.2.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.yellow)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(device.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                            Text(device.localIP)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(MiBarSecondaryButtonStyle())
            }

            HStack(spacing: 8) {
                if store.isCloudLoginActive {
                    if let loginURL = store.qrLoginURL {
                        Button {
                            NSWorkspace.shared.open(loginURL)
                        } label: {
                            Label("浏览器打开", systemImage: "safari")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(MiBarSecondaryButtonStyle())
                    }

                    Button {
                        store.cancelCloudQRLogin()
                    } label: {
                        Text("取消")
                            .frame(maxWidth: store.qrLoginURL != nil ? 64 : .infinity)
                    }
                    .buttonStyle(MiBarSecondaryButtonStyle())
                } else {
                    Button {
                        store.startCloudQRLogin()
                    } label: {
                        Label("米家扫码快速获取", systemImage: "qrcode.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MiBarSecondaryButtonStyle())
                }
            }

            Spacer()
        }
    }
}

private struct MenuItemRow: View {
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
            .contentShape(
                Rectangle()
            )
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
