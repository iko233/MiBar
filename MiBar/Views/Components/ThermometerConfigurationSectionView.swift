import SwiftUI

/// 全新扫描驱动型温湿度计配置中心。
/// 核心理念：“添加设备都应该从扫描获取相应的信息”，通过 BLE 广播雷达与云端设备库自动对齐。
struct ThermometerConfigurationSectionView: View {
    @Bindable var store: ThermometerStore
    @State private var isKeyVisible = false
    @State private var isRefreshing = false
    @State private var isManualInputExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.isEditingConfiguration {
                editingFormView
            } else {
                mainScanningView
            }
        }
    }

    // MARK: - 主扫描与设备列表视图

    private var mainScanningView: some View {
        VStack(spacing: 12) {
            // 顶部状态栏与雷达刷新
            headerStatusSection

            // 1. 附近蓝牙扫描发现的设备区（雷达扫描捕获）
            nearbyDiscoveredSection

            // 2. 已添加并正在运行的设备列表
            if !store.devices.isEmpty {
                configuredDevicesSection
            }

            // 3. 云端已同步但尚未添加的设备列表
            cloudAvailableSection

            // 4. 菜单栏显示设置
            Divider()
                .opacity(0.2)
                .padding(.vertical, 2)

            menuBarDisplayToggle

            // 5. 高级：手动填入折叠入口
            manualInputAccordion
        }
    }

    // MARK: - 顶部状态栏

    private var headerStatusSection: some View {
        HStack {
            HStack(spacing: 5) {
                Circle()
                    .fill(store.isScanning ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)

                Text(store.isScanning ? "正在扫描周围温湿度广播" : store.statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.4)) {
                    isRefreshing = true
                }
                store.restartScanning()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation {
                        isRefreshing = false
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    Text("重新扫描")
                        .font(.system(size: 10.5))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 2)
    }

    // MARK: - 附近蓝牙扫描发现区域 (BLE Radar)

    private var nearbyDiscoveredSection: some View {
        let unaddedNearby = store.discoveredBLEDevices.filter { ble in
            !store.devices.contains(where: { $0.normalizedMAC == ble.mac })
        }

        return VStack(alignment: .leading, spacing: 6) {
            if !unaddedNearby.isEmpty {
                HStack {
                    Label("发现附近的米家设备 (\(unaddedNearby.count))", systemImage: "dot.radiowaves.left.and.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer()
                }

                VStack(spacing: 6) {
                    ForEach(unaddedNearby) { bleDev in
                        nearbyDeviceRow(bleDev)
                    }
                }
            } else if store.devices.isEmpty {
                // 附近未扫描到且尚未配置任何设备时，展示雷达等待动画
                scanningRadarPlaceholder
            }
        }
    }

    private func nearbyDeviceRow(_ bleDev: DiscoveredBLEDevice) -> some View {
        let matchedCloud = store.matchCloudRecord(for: bleDev.mac)
        let hasKey = matchedCloud?.bindKey.isEmpty == false

        return HStack(spacing: 8) {
            // 信号强度图标
            VStack(spacing: 1) {
                Image(systemName: signalIconName(level: bleDev.signalLevel))
                    .font(.system(size: 11))
                    .foregroundStyle(bleDev.signalLevel >= 3 ? Color.green : Color.orange)
                Text("\(bleDev.rssi)dB")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 28)

            // 设备型号与 MAC
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(matchedCloud?.name ?? bleDev.modelType.rawValue)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(bleDev.modelType.shortName)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background {
                            Capsule().fill(Color.primary.opacity(0.06))
                        }
                }

                HStack(spacing: 6) {
                    Text(bleDev.formattedMAC)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.secondary)

                    if hasKey {
                        HStack(spacing: 2) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 8))
                            Text("密钥已就绪")
                                .font(.system(size: 8.5, weight: .medium))
                        }
                        .foregroundStyle(.green)
                    }
                }
            }

            Spacer()

            // 一键添加按钮
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    store.addFromDiscoveredBLE(bleDev)
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 10))
                    Text(hasKey ? "一键添加" : "添加设备")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    Capsule().fill(hasKey ? Color.blue.opacity(0.18) : Color.primary.opacity(0.08))
                }
                .foregroundStyle(hasKey ? Color.blue : Color.primary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hasKey ? Color.blue.opacity(0.05) : Color.primary.opacity(0.035))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(hasKey ? Color.blue.opacity(0.20) : Color.primary.opacity(0.06), lineWidth: 0.8)
        }
    }

    private var scanningRadarPlaceholder: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text("正在扫描附近的温湿度计广播…")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.primary)

                Text("请确保设备在 Mac 蓝牙范围内，广播将自动出现在此处。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        }
    }

    // MARK: - 已添加的设备列表 (Configured Devices)

    private var configuredDevicesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("已添加设备 (\(store.devices.count))")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            VStack(spacing: 7) {
                ForEach(store.devices) { device in
                    configuredDeviceCard(device: device)
                }
            }
        }
    }

    private func configuredDeviceCard(device: ThermometerDevice) -> some View {
        let reading = store.reading(for: device)
        let isPrimary = device.isPrimary

        return VStack(spacing: 6) {
            // 顶栏：绿点、名称、型号、主设备标
            HStack(spacing: 6) {
                Circle()
                    .fill(reading != nil ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)

                Text(device.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(device.modelType.shortName)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background {
                        Capsule().fill(Color.primary.opacity(0.06))
                    }

                Spacer()

                if isPrimary {
                    Text("主显示")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background {
                            Capsule().fill(Color.blue.opacity(0.12))
                        }
                } else {
                    Button("设为主设备") {
                        store.setPrimaryDevice(mac: device.normalizedMAC)
                    }
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                }
            }

            // 中栏：大号温湿度显示与电量
            HStack {
                HStack(spacing: 8) {
                    Text(reading?.temperatureString ?? "--.-°C")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)

                    Text(reading?.humidityString ?? "--%")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.cyan)
                }

                Spacer()

                if let battery = reading?.battery {
                    HStack(spacing: 3) {
                        Image(systemName: battery > 20 ? "battery.100" : "battery.25")
                            .font(.system(size: 10))
                            .foregroundStyle(battery > 20 ? Color.green : Color.red)
                        Text("\(battery)%")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                if let reading {
                    Text(reading.relativeTimeString)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 4)
                }
            }

            // 底栏：MAC 与操作
            HStack {
                Text("MAC: \(device.formattedMAC)")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("重命名 / 密钥") {
                    store.beginEditing(device: device)
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)

                Button("移除") {
                    store.deleteDevice(mac: device.normalizedMAC)
                }
                .font(.system(size: 10))
                .foregroundStyle(.red)
                .buttonStyle(.plain)
                .padding(.leading, 6)
            }
        }
        .padding(9)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isPrimary ? Color.blue.opacity(0.25) : Color.primary.opacity(0.07), lineWidth: 1)
        }
    }

    // MARK: - 云端已关联但未添加的设备列表

    @ViewBuilder
    private var cloudAvailableSection: some View {
        let unaddedCloud = store.cachedCloudThermometers.filter { cloud in
            !store.devices.contains(where: { $0.normalizedMAC == cloud.normalizedMAC })
        }

        if !unaddedCloud.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("米家账号已同步的设备 (\(unaddedCloud.count))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)

                VStack(spacing: 5) {
                    ForEach(unaddedCloud) { record in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(record.name)
                                        .font(.system(size: 11.5, weight: .medium))
                                    Text(record.modelType.shortName)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                                Text("MAC: \(record.formattedMAC)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer()

                            Button("一键添加") {
                                withAnimation {
                                    store.addFromCloudRecord(record)
                                }
                            }
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background {
                                Capsule().fill(Color.blue.opacity(0.15))
                            }
                            .foregroundStyle(.blue)
                            .buttonStyle(.plain)
                        }
                        .padding(8)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(0.03))
                        }
                    }
                }
            }
        }
    }

    // MARK: - 菜单栏常驻开关

    private var menuBarDisplayToggle: some View {
        Toggle("在菜单栏图标旁显示主设备温湿度", isOn: Binding(
            get: { store.configuration.showInMenuBar },
            set: {
                var updated = store.configuration
                updated.showInMenuBar = $0
                store.configuration = updated
                LocalConfigStore.saveThermometerConfig(updated)
            }
        ))
        .toggleStyle(.switch)
        .controlSize(.mini)
        .font(.system(size: 11))
        .padding(.horizontal, 2)
    }

    // MARK: - 高级手动填写折叠区域

    private var manualInputAccordion: some View {
        VStack(spacing: 6) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    isManualInputExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: isManualInputExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                    Text("高级：手动输入 MAC / BindKey")
                        .font(.system(size: 10.5))
                    Spacer()
                }
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 2)
            }
            .buttonStyle(.plain)

            if isManualInputExpanded {
                Button {
                    store.beginAddingNewDevice()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 10))
                        Text("手动填写新设备密钥")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.glass)
                .padding(.top, 2)
            }
        }
    }

    // MARK: - 编辑表单视图 (Editing Form)

    private var editingFormView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(store.editingDeviceID == nil ? "手动配置温湿度计" : "修改温湿度计信息")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Button("取消") {
                    store.cancelEditing()
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            }

            // 设备型号选择
            VStack(alignment: .leading, spacing: 4) {
                Text("设备型号")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    ForEach([ThermometerModelType.v3Mini, ThermometerModelType.v3, ThermometerModelType.v2], id: \.self) { model in
                        let isSelected = store.draftModelType == model
                        Button {
                            store.draftModelType = model
                            if store.draftName.isEmpty || ThermometerModelType.allCases.map(\.rawValue).contains(store.draftName) {
                                store.draftName = model.rawValue
                            }
                        } label: {
                            Text(model.shortName)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 26)
                                .background {
                                    if isSelected {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(Color.primary.opacity(0.08))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.8)
                                            }
                                    }
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                }
            }

            // 自定义名称
            VStack(alignment: .leading, spacing: 4) {
                Text("设备名称")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("例: 书房 3 mini", text: $store.draftName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.045))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }
            }

            // MAC 地址
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("MAC 地址")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    let cleanedCount = store.draftMAC.filter { $0.isLetter || $0.isNumber }.count
                    if cleanedCount == 12 {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "sensor.tag.radiowaves.forward")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)

                    TextField("例: AA:BB:CC:DD:EE:FF", text: $store.draftMAC)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5, design: .monospaced))

                    Button {
                        store.pasteMACFromClipboard()
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 9))
                            Text("粘贴")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background {
                            Capsule().fill(Color.primary.opacity(0.06))
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
            }

            // BindKey
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("BindKey (32 位 Hex)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    let keyCount = store.draftBindKey.filter { $0.isLetter || $0.isNumber }.count
                    Text("\(keyCount)/32")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(keyCount == 32 ? Color.green : (keyCount > 0 ? Color.orange : Color.secondary))
                }

                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)

                    if isKeyVisible {
                        TextField("32 位密钥", text: $store.draftBindKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11.5, design: .monospaced))
                    } else {
                        SecureField("32 位密钥", text: $store.draftBindKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11.5, design: .monospaced))
                    }

                    Button {
                        isKeyVisible.toggle()
                    } label: {
                        Image(systemName: isKeyVisible ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.pasteBindKeyFromClipboard()
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 9))
                            Text("粘贴")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background {
                            Capsule().fill(Color.primary.opacity(0.06))
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
            }

            // 保存与取消按钮
            let isFormValid = store.draftMAC.filter { $0.isLetter || $0.isNumber }.count == 12
                && store.draftBindKey.filter { $0.isLetter || $0.isNumber }.count == 32

            HStack(spacing: 8) {
                Button("保存并启用") {
                    store.saveDraftConfiguration()
                }
                .buttonStyle(MiBarPrimaryButtonStyle())
                .disabled(!isFormValid)
            }
            .padding(.top, 4)
        }
    }

    private func signalIconName(level: Int) -> String {
        switch level {
        case 4: return "cellularbars"
        case 3: return "chart.bar.fill"
        default: return "chart.bar"
        }
    }
}
