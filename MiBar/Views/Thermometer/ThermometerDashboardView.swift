import SwiftUI

/// 专为 macOS 菜单栏弹窗设计的自适应环境温湿度看板视图。
/// 支持单设备大卡片与多设备（如 3 mini + 3 代）双列紧凑高质感毛玻璃并排卡片。
struct ThermometerDashboardView: View {
    @Bindable var store: LightStore
    @Bindable var thermometerStore: ThermometerStore

    var body: some View {
        let devices = thermometerStore.devices.filter { $0.isValid }

        if devices.count == 1, let singleDev = devices.first {
            singleDeviceCard(device: singleDev)
        } else if devices.count == 2 {
            dualDeviceCards(devices: devices)
        } else if devices.count > 2 {
            multiDeviceGrid(devices: devices)
        }
    }

    // MARK: - Single Device Large Capsule Card

    private func singleDeviceCard(device: ThermometerDevice) -> some View {
        let reading = thermometerStore.reading(for: device)
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                store.targetDetailDeviceMAC = device.normalizedMAC
                store.isEditingConfiguration = true
            }
        } label: {
            HStack(spacing: 8) {
                // 温度
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.orange.opacity(0.16))
                        .frame(width: 22, height: 22)
                        .overlay {
                            Image(systemName: "thermometer.medium")
                                .foregroundStyle(.orange)
                                .font(.system(size: 11, weight: .semibold))
                        }

                    Text(reading?.temperatureString ?? "--.-°C")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }

                Spacer()

                // 细分隔线
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1, height: 16)

                Spacer()

                // 湿度
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.cyan.opacity(0.16))
                        .frame(width: 22, height: 22)
                        .overlay {
                            Image(systemName: "humidity.fill")
                                .foregroundStyle(.cyan)
                                .font(.system(size: 10, weight: .semibold))
                        }

                    Text(reading?.humidityString ?? "--%")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }

                if let battery = reading?.battery {
                    Spacer()

                    // 电量
                    HStack(spacing: 3) {
                        Image(systemName: battery > 20 ? "battery.100" : "battery.25")
                            .foregroundStyle(battery > 20 ? Color.secondary : Color.red)
                            .font(.system(size: 10))
                        Text("\(battery)%")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                glassBackground
            }
            .overlay {
                glassBorder
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("\(device.name) · 点击查看配置与详情")
    }

    // MARK: - Dual Device Compact Cards (左右等宽 1:1 双列毛玻璃并排)

    private func dualDeviceCards(devices: [ThermometerDevice]) -> some View {
        HStack(spacing: 8) {
            ForEach(devices.prefix(2)) { device in
                compactDeviceCard(device: device)
            }
        }
    }

    private func compactDeviceCard(device: ThermometerDevice) -> some View {
        let reading = thermometerStore.reading(for: device)
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                store.targetDetailDeviceMAC = device.normalizedMAC
                store.isEditingConfiguration = true
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                // 设备名与型号角标
                HStack(spacing: 4) {
                    Circle()
                        .fill(reading != nil ? Color.green : Color.orange)
                        .frame(width: 5, height: 5)

                    Text(device.name)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if let battery = reading?.battery {
                        Text("\(battery)%")
                            .font(.system(size: 9, weight: .regular, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                }

                // 温湿度双核心指标
                HStack(spacing: 6) {
                    HStack(spacing: 2) {
                        Image(systemName: "thermometer.medium")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                        Text(reading?.temperatureString ?? "--.-°")
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 2) {
                        Image(systemName: "humidity.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.cyan)
                        Text(reading?.humidityString ?? "--%")
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background {
                glassBackground
            }
            .overlay {
                glassBorder
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("\(device.name) · \(device.modelType.rawValue)")
    }

    // MARK: - Multi Device Grid (3 台及以上)

    private func multiDeviceGrid(devices: [ThermometerDevice]) -> some View {
        VStack(spacing: 6) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 6) {
                ForEach(devices) { device in
                    compactDeviceCard(device: device)
                }
            }
        }
    }

    // MARK: - Glassmorphic Styling

    private var glassBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            }
            .overlay {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.14),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .center
                )
            }
    }

    private var glassBorder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8)
    }
}
