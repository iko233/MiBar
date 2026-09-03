import AppKit
import SwiftUI

/// 统一设备列表视图组件
/// 汇集展示挂灯与各温湿度计的实时连接状态、大字指标与快捷添加入口。
struct UnifiedDeviceListView: View {
    @Bindable var store: LightStore
    @Bindable var thermometerStore: ThermometerStore
    let onNavigate: (ConfigurationPage) -> Void
    let onFinish: () -> Void

    @State private var isBackHovered = false
    @State private var isAddHovered = false

    private var totalDeviceCount: Int {
        (store.isLightConfigured ? 1 : 0) + thermometerStore.devices.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - Header Bar
            headerBar

            // MARK: - Device Cards List
            VStack(spacing: 8) {
                if store.isLightConfigured {
                    lightDeviceRow
                }

                ForEach(thermometerStore.devices) { device in
                    thermometerDeviceRow(device: device)
                }
            }

            // MARK: - Nearby Radar Quick Shelf
            nearbyBLEQuickShelf

            Divider()
                .opacity(0.2)
                .padding(.vertical, 2)

            // MARK: - Menu Bar Display Row
            menuBarDisplayRow
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 8) {
            Button {
                onFinish()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("完成")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .frame(height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isBackHovered ? Color.primary.opacity(0.08) : Color.clear)
                }
            }
            .buttonStyle(.plain)
            .onHover { isBackHovered = $0 }

            Spacer()

            Text("已连接设备 (\(totalDeviceCount))")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            Button {
                withAnimation {
                    store.startCloudQRLogin()
                    onNavigate(.scanImport)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("扫码添加")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 8)
                .frame(height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isAddHovered ? Color.accentColor.opacity(0.12) : Color.accentColor.opacity(0.06))
                }
            }
            .buttonStyle(.plain)
            .onHover { isAddHovered = $0 }
        }
    }

    // MARK: - Light Device Row

    private var lightDeviceRow: some View {
        Button {
            withAnimation {
                onNavigate(.lightDetail)
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                // 第一行：图标 + 设备名 + 标签 ---------> 在线状态点 + 箭头
                HStack(spacing: 5) {
                    Image(systemName: "lightbulb.2.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.yellow)
                        .frame(width: 16)

                    Text("米家智能显示器挂灯 1S")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("Wi-Fi")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))

                    Spacer(minLength: 4)

                    Circle()
                        .fill(store.isConnected ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }

                // 第二行：IP 地址 ---------------------> 开关状态与亮度
                HStack(alignment: .firstTextBaseline) {
                    Text("IP: \(store.host.isEmpty ? "未配置" : store.host)")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(store.isConnected ? (store.state.isOn ? "已开灯 · 亮度 \(store.state.brightness)%" : "已关灯 (待机)") : "未连接")
                        .font(.system(size: 10))
                        .foregroundStyle(store.isConnected ? Color.secondary : Color.orange)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Thermometer Device Row

    private func thermometerDeviceRow(device: ThermometerDevice) -> some View {
        let reading = thermometerStore.reading(for: device)
        let isPrimary = thermometerStore.primaryDevice?.normalizedMAC == device.normalizedMAC

        return Button {
            withAnimation {
                store.targetDetailDeviceMAC = nil
                thermometerStore.beginEditing(device: device)
                onNavigate(.thermometerDetail(mac: device.normalizedMAC))
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                // 第一行：图标 + 设备名 + 型号徽标 + 主显示徽标 ---------> 状态点 + 箭头
                HStack(spacing: 5) {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.cyan)
                        .frame(width: 16)

                    Text(device.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(device.modelType.shortName)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))

                    if isPrimary {
                        Text("主显示")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(Color.blue)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.blue.opacity(0.12)))
                    }

                    Spacer(minLength: 4)

                    Circle()
                        .fill(reading != nil ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }

                // 第二行：MAC 地址 ------------------------------------> 实时温湿度读数与电量
                HStack(alignment: .firstTextBaseline) {
                    Text(device.formattedMAC)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if let reading {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(reading.temperatureString)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)

                            Text(reading.humidityString)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)

                            if let bat = reading.battery {
                                Text("\(bat)%")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .lineLimit(1)
                    } else {
                        Text("等待广播数据...")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isPrimary ? Color.blue.opacity(0.28) : Color.primary.opacity(0.08), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Nearby BLE Quick Shelf

    @ViewBuilder
    private var nearbyBLEQuickShelf: some View {
        let unaddedBLE = thermometerStore.discoveredBLEDevices.filter { ble in
            !thermometerStore.devices.contains(where: { $0.normalizedMAC == ble.mac })
        }

        if !unaddedBLE.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.cyan)
                    Text("附近发现的新设备 (\(unaddedBLE.count))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)

                ForEach(unaddedBLE) { bleDev in
                    HStack(spacing: 8) {
                        Text(bleDev.modelType.shortName)
                            .font(.system(size: 11.5, weight: .medium))
                        Text(bleDev.formattedMAC)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("一键添加") {
                            thermometerStore.addFromDiscoveredBLE(bleDev)
                        }
                        .font(.system(size: 10.5, weight: .medium))
                        .buttonStyle(MiBarSecondaryButtonStyle())
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.cyan.opacity(0.04))
                    }
                }
            }
        }
    }

    // MARK: - Menu Bar Display Toggle

    private var menuBarDisplayRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("在菜单栏显示主设备温湿度")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.primary)
                Text("在顶部状态栏图标旁常驻呈现温度与湿度数值")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { thermometerStore.configuration.showInMenuBar },
                set: {
                    var updated = thermometerStore.configuration
                    updated.showInMenuBar = $0
                    thermometerStore.configuration = updated
                    LocalConfigStore.saveThermometerConfig(updated)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.horizontal, 2)
    }
}
