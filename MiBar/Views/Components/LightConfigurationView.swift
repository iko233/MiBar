import AppKit
import SwiftUI

/// 统一配置中心页面导航枚举
enum ConfigurationPage: Hashable {
    case list
    case scanImport
    case lightDetail
    case thermometerDetail(mac: String)
}

/// 统一设备管理与配置中心
/// 废除原有顶部 Tab 切换，按设备状态分流：无设备直出扫码选择导入，有设备展示统一列表，点击项进入二级详情修改或移除。
struct LightConfigurationView: View {
    @Bindable var store: LightStore
    @Bindable var thermometerStore: ThermometerStore
    @Binding var isConfirmingClearConfiguration: Bool

    @State private var currentPage: ConfigurationPage? = nil
    @State private var isTokenVisible = false
    @State private var isKeyVisible = false
    @State private var isBackHovered = false
    @State private var isAddHovered = false

    /// 是否已配置了任何设备（挂灯或温湿度计）
    private var hasAnyConfiguredDevice: Bool {
        store.isLightConfigured || !thermometerStore.devices.isEmpty
    }

    /// 当前激活的页面状态
    private var activePage: ConfigurationPage {
        if let targetMAC = store.targetDetailDeviceMAC {
            return .thermometerDetail(mac: targetMAC)
        }
        if let currentPage {
            return currentPage
        }
        return hasAnyConfiguredDevice ? .list : .scanImport
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch activePage {
            case .list:
                unifiedListView
            case .scanImport:
                unifiedScanImportView
            case .lightDetail:
                lightDetailView
            case .thermometerDetail(let mac):
                thermometerDetailView(mac: mac)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: activePage)
    }

    // MARK: - 1. 统一设备列表页 (Unified Device List)

    private var unifiedListView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 顶栏
            HStack(spacing: 8) {
                Button {
                    store.isEditingConfiguration = false
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

                let totalCount = (store.isLightConfigured ? 1 : 0) + thermometerStore.devices.count
                Text("已连接设备 (\(totalCount))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    withAnimation {
                        store.startCloudQRLogin()
                        currentPage = .scanImport
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("添加")
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

            // 设备卡片列表
            VStack(spacing: 8) {
                // 挂灯设备项
                if store.isLightConfigured {
                    lightDeviceRow
                }

                // 各温湿度计设备项
                ForEach(thermometerStore.devices) { device in
                    thermometerDeviceRow(device: device)
                }
            }

            // 快捷发现架：雷达扫描到的未添加 BLE 设备
            nearbyBLEQuickShelf

            Divider()
                .opacity(0.2)
                .padding(.vertical, 2)

            // 全局菜单栏显示开关
            menuBarDisplayRow
        }
    }

    /// 挂灯设备列表项
    private var lightDeviceRow: some View {
        Button {
            withAnimation {
                currentPage = .lightDetail
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.yellow.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: "lightbulb.2.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.yellow)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text("米家智能显示器挂灯 1S")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.primary)

                        Text("Wi-Fi 直连")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }

                    Text("IP: \(store.host) · \(store.isConnected ? "已在线连接" : "未连接")")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Circle()
                    .fill(store.isConnected ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
    }

    /// 温湿度计列表项
    private func thermometerDeviceRow(device: ThermometerDevice) -> some View {
        let reading = thermometerStore.reading(for: device)
        let isPrimary = thermometerStore.primaryDevice?.normalizedMAC == device.normalizedMAC

        return Button {
            withAnimation {
                store.targetDetailDeviceMAC = nil
                thermometerStore.beginEditing(device: device)
                currentPage = .thermometerDetail(mac: device.normalizedMAC)
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.cyan.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 15))
                        .foregroundStyle(.cyan)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(device.name)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.primary)

                        Text(device.modelType.shortName)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))

                        if isPrimary {
                            Text("主显示")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color.blue)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.blue.opacity(0.12)))
                        }
                    }

                    Text("MAC: \(device.formattedMAC)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // 读数展示
                if let reading {
                    VStack(alignment: .trailing, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(reading.temperatureString)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text(reading.humidityString)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }

                        if let bat = reading.battery {
                            Text("电量 \(bat)%")
                                .font(.system(size: 8.5))
                                .foregroundStyle(.tertiary)
                        }
                    }
                } else {
                    Text("--.-°C")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                }

                Circle()
                    .fill(reading != nil ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isPrimary ? Color.blue.opacity(0.25) : Color.primary.opacity(0.08), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
    }

    /// 附近未添加的 BLE 温湿度计快捷发现架
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

    /// 菜单栏温湿度显示总开关
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

    // MARK: - 2. 米家扫码快速导入与设备选择页 (Scan Import)

    private var unifiedScanImportView: some View {
        VStack(alignment: .leading, spacing: 11) {
            // 顶栏
            HStack(spacing: 8) {
                if hasAnyConfiguredDevice {
                    Button {
                        withAnimation {
                            currentPage = .list
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                            Text("列表")
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
                }

                Spacer()

                Text("米家扫码导入设备")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                if hasAnyConfiguredDevice {
                    Color.clear.frame(width: 70, height: 32)
                }
            }

            // 二维码展示或扫码指引
            if let imageData = store.qrImageData,
               let image = NSImage(data: imageData) {
                VStack(spacing: 6) {
                    HStack {
                        Spacer()
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: 140, height: 140)
                            .padding(8)
                            .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                        Spacer()
                    }

                    Text("请使用米家 App 扫码并确认登录")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)

                    Text("系统将自动读取你名下的挂灯与温湿度计密钥")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            // 登录状态提示
            if !store.cloudLoginStatus.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    if store.isCloudLoginActive {
                        ProgressView().controlSize(.small).padding(.top, 1)
                    } else {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.top, 1)
                    }

                    Text(store.cloudLoginStatus)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // MARK: 扫码结果：让用户选择需要添加的设备
            let hasDiscoveredItems = !store.cloudDevices.isEmpty || !store.scannedCloudThermometers.isEmpty
            if hasDiscoveredItems {
                VStack(alignment: .leading, spacing: 8) {
                    Text("请选择需要添加的设备：")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.top, 4)

                    // 1. 挂灯候选
                    ForEach(store.cloudDevices) { light in
                        let isAdded = store.isLightConfigured && store.host == light.localIP
                        HStack(spacing: 8) {
                            Image(systemName: "lightbulb.2.fill")
                                .foregroundStyle(.yellow)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(light.name)
                                    .font(.system(size: 11.5, weight: .medium))
                                Text(light.localIP.isEmpty ? "由米家云端提供" : light.localIP)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if isAdded {
                                Text("已添加")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            } else {
                                Button("添加") {
                                    Task {
                                        await store.importCloudDevice(light)
                                        withAnimation { currentPage = .list }
                                    }
                                }
                                .buttonStyle(MiBarPrimaryButtonStyle())
                                .controlSize(.small)
                            }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                    }

                    // 2. 温湿度计候选
                    ForEach(store.scannedCloudThermometers) { record in
                        let isAdded = thermometerStore.devices.contains(where: { $0.normalizedMAC == record.normalizedMAC })
                        HStack(spacing: 8) {
                            Image(systemName: "thermometer.medium")
                                .foregroundStyle(.cyan)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Text(record.name)
                                        .font(.system(size: 11.5, weight: .medium))
                                    Text(record.modelType.shortName)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                                Text("MAC: \(record.formattedMAC)")
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if isAdded {
                                Text("已添加")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            } else {
                                Button("添加") {
                                    thermometerStore.addFromCloudRecord(record)
                                    withAnimation { currentPage = .list }
                                }
                                .buttonStyle(MiBarPrimaryButtonStyle())
                                .controlSize(.small)
                            }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                    }

                    Button {
                        withAnimation { currentPage = .list }
                    } label: {
                        Text("进入设备列表")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MiBarSecondaryButtonStyle())
                    .padding(.top, 4)
                }
            }

            // 底部操作区
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

                    //Button("取消") {
                    //    store.cancelCloudQRLogin()
                    //}
                    //.buttonStyle(MiBarSecondaryButtonStyle())
                    //.frame(maxWidth: store.qrLoginURL != nil ? 64 : .infinity)
                } else if !hasDiscoveredItems {
                    Button {
                        store.startCloudQRLogin()
                    } label: {
                        Label("米家扫码快速获取", systemImage: "qrcode.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MiBarPrimaryButtonStyle())
                }
            }
        }
    }

    // MARK: - 3. 挂灯详情与配置更新 (Light Detail)

    private var lightDetailView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 顶栏
            HStack(spacing: 8) {
                Button {
                    withAnimation { currentPage = .list }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("列表")
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

                Text("挂灯 1S 详情配置")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Color.clear.frame(width: 70, height: 32)
            }

            // 参数输入区
            VStack(alignment: .leading, spacing: 8) {
                Text("局域网直连参数")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                // IP
                HStack(spacing: 8) {
                    Image(systemName: "network")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    TextField("挂灯 IPv4 地址 (例: 192.168.31.200)", text: $store.host)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))

                    if !store.host.isEmpty {
                        Button { store.host = "" } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.045)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))

                // Token
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
                        Button { isTokenVisible.toggle() } label: {
                            Image(systemName: isTokenVisible ? "eye.slash.fill" : "eye.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        Button { store.tokenHex = "" } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.045)))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(!store.tokenHex.isEmpty && store.tokenHex.count != 32 ? Color.orange.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1)
                )
            }

            // 操作按钮
            HStack(spacing: 8) {
                Button {
                    Task {
                        await store.saveConfiguration()
                        withAnimation { currentPage = .list }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if store.isWorking {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text("保存并连接")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(MiBarPrimaryButtonStyle())
                .disabled(!store.isConfigured || store.isWorking)

                Button(role: .destructive) {
                    store.removeLightDevice()
                    withAnimation {
                        currentPage = hasAnyConfiguredDevice ? .list : .scanImport
                    }
                } label: {
                    Text("移除挂灯")
                        .foregroundStyle(.red)
                }
                .buttonStyle(MiBarDestructiveButtonStyle())
            }
        }
    }

    // MARK: - 4. 温湿度计详情与配置更新 (Thermometer Detail)

    private func thermometerDetailView(mac: String) -> some View {
        let cleanMAC = mac.uppercased().filter { ("0"..."9").contains($0) || ("A"..."F").contains($0) }
        guard let device = thermometerStore.devices.first(where: { $0.normalizedMAC == cleanMAC }) else {
            return AnyView(
                VStack {
                    Text("设备不存在或已移除")
                        .font(.system(size: 12))
                    Button("返回列表") {
                        store.targetDetailDeviceMAC = nil
                        currentPage = .list
                    }
                }
            )
        }

        let reading = thermometerStore.reading(for: device)
        let isPrimary = thermometerStore.primaryDevice?.normalizedMAC == device.normalizedMAC

        return AnyView(
            VStack(alignment: .leading, spacing: 12) {
                // 顶栏
                HStack(spacing: 8) {
                    Button {
                        withAnimation {
                            store.targetDetailDeviceMAC = nil
                            currentPage = .list
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                            Text("列表")
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

                    Text(device.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Color.clear.frame(width: 70, height: 32)
                }

                // 实时数据监控卡片
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前温度")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(reading?.temperatureString ?? "--.-°C")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                    }

                    Divider().frame(height: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前湿度")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(reading?.humidityString ?? "--%")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        Circle()
                            .fill(reading != nil ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)

                        if let bat = reading?.battery {
                            Text("电量 \(bat)%")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.04)))

                // 参数表单
                VStack(alignment: .leading, spacing: 8) {
                    // 设备名称
                    VStack(alignment: .leading, spacing: 3) {
                        Text("设备名称")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        TextField("设备名称", text: $thermometerStore.draftName)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 8)
                            .frame(height: 32)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.045)))
                    }

                    // 设为主显示设备
                    HStack {
                        Text("设为主显示设备")
                            .font(.system(size: 11))
                        Spacer()
                        if isPrimary {
                            Text("当前主设备")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.blue)
                        } else {
                            Button("设为主设备") {
                                thermometerStore.setPrimaryDevice(mac: cleanMAC)
                            }
                            .buttonStyle(MiBarSecondaryButtonStyle())
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 2)

                    // MAC 地址
                    VStack(alignment: .leading, spacing: 3) {
                        Text("MAC 地址")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        TextField("MAC 地址", text: $thermometerStore.draftMAC)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11.5, design: .monospaced))
                            .padding(.horizontal, 8)
                            .frame(height: 32)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.045)))
                    }

                    // 32 位 BindKey
                    VStack(alignment: .leading, spacing: 3) {
                        Text("32 位 BindKey (加密解密密钥)")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            if isKeyVisible {
                                TextField("32 位 BindKey", text: $thermometerStore.draftBindKey)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11, design: .monospaced))
                            } else {
                                SecureField("32 位 BindKey", text: $thermometerStore.draftBindKey)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11))
                            }

                            Button { isKeyVisible.toggle() } label: {
                                Image(systemName: isKeyVisible ? "eye.slash.fill" : "eye.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.045)))
                    }
                }

                // 操作按钮
                HStack(spacing: 8) {
                    Button {
                        thermometerStore.saveDraftConfiguration()
                        withAnimation {
                            store.targetDetailDeviceMAC = nil
                            currentPage = .list
                        }
                    } label: {
                        Text("保存修改")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MiBarPrimaryButtonStyle())

                    Button(role: .destructive) {
                        thermometerStore.deleteDevice(mac: cleanMAC)
                        withAnimation {
                            store.targetDetailDeviceMAC = nil
                            currentPage = hasAnyConfiguredDevice ? .list : .scanImport
                        }
                    } label: {
                        Text("移除设备")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(MiBarDestructiveButtonStyle())
                }
            }
        )
    }
}
