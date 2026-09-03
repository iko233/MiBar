import AppKit
import SwiftUI

/// 温湿度计详情监控与参数修改组件
struct ThermometerDetailView: View {
    let mac: String
    @Bindable var store: ThermometerStore
    let onBack: () -> Void
    let onDeviceRemoved: () -> Void

    @State private var isKeyVisible = false
    @State private var isBackHovered = false

    private var cleanMAC: String {
        mac.uppercased().filter { ("0"..."9").contains($0) || ("A"..."F").contains($0) }
    }

    private var device: ThermometerDevice? {
        store.devices.first(where: { $0.normalizedMAC == cleanMAC })
    }

    var body: some View {
        if let device {
            detailFormView(device: device)
        } else {
            notFoundView
        }
    }

    // MARK: - Detail Form View

    private func detailFormView(device: ThermometerDevice) -> some View {
        let reading = store.reading(for: device)
        let isPrimary = store.primaryDevice?.normalizedMAC == device.normalizedMAC

        return VStack(alignment: .leading, spacing: 12) {
            // 顶栏
            HStack(spacing: 8) {
                Button {
                    withAnimation { onBack() }
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
                    TextField("设备名称", text: $store.draftName)
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
                            store.setPrimaryDevice(mac: cleanMAC)
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
                    TextField("MAC 地址", text: $store.draftMAC)
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
                            TextField("32 位 BindKey", text: $store.draftBindKey)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11, design: .monospaced))
                        } else {
                            SecureField("32 位 BindKey", text: $store.draftBindKey)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                        }

                        Button {
                            isKeyVisible.toggle()
                        } label: {
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
                    store.saveDraftConfiguration()
                    withAnimation { onBack() }
                } label: {
                    Text("保存修改")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MiBarPrimaryButtonStyle())

                Button(role: .destructive) {
                    store.deleteDevice(mac: cleanMAC)
                    withAnimation { onDeviceRemoved() }
                } label: {
                    Text("移除设备")
                        .foregroundStyle(.red)
                }
                .buttonStyle(MiBarDestructiveButtonStyle())
            }
        }
    }

    // MARK: - Not Found View

    private var notFoundView: some View {
        VStack(spacing: 12) {
            Text("设备不存在或已移除")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Button("返回列表") {
                onBack()
            }
            .buttonStyle(MiBarSecondaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
