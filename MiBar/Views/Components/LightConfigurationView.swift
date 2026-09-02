import AppKit
import SwiftUI

/// 设备配置视图（IP/Token 本地参数填写与米家二维码扫码导入）
struct LightConfigurationView: View {
    @Bindable var store: LightStore
    @Binding var isConfirmingClearConfiguration: Bool

    @State private var isTokenVisible = false
    @State private var isBackHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - Header
            headerBar

            // MARK: - Local LAN Parameters
            lanParametersSection

            // MARK: - Save & Clear Actions
            actionButtons

            Divider()
                .opacity(0.25)
                .padding(.vertical, 2)

            // MARK: - Cloud QR Import Section
            CloudImportSectionView(store: store)
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
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
    }

    // MARK: - LAN Parameters

    private var lanParametersSection: some View {
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
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
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
    }
}

// MARK: - Cloud Import Section View

/// 小米账号二维码登录与云端设备发现组件
struct CloudImportSectionView: View {
    @Bindable var store: LightStore

    var body: some View {
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
