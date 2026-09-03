import AppKit
import SwiftUI

/// 挂灯 1S 详情参数配置与移除组件
struct LightDetailView: View {
    @Bindable var store: LightStore
    let onBack: () -> Void
    let onDeviceRemoved: () -> Void

    @State private var isTokenVisible = false
    @State private var isBackHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - Header Bar
            headerBar

            // MARK: - LAN Parameters Input
            lanParametersSection

            // MARK: - Action Buttons
            actionButtons
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
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

            Text("挂灯 1S 详情配置")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            Color.clear.frame(width: 70, height: 32)
        }
    }

    // MARK: - Parameters Input

    private var lanParametersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("局域网直连参数")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            // IP 地址输入
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
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))

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

                    Button {
                        store.tokenHex = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
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
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    await store.saveConfiguration()
                    withAnimation { onBack() }
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
                withAnimation { onDeviceRemoved() }
            } label: {
                Text("移除挂灯")
                    .foregroundStyle(.red)
            }
            .buttonStyle(MiBarDestructiveButtonStyle())
        }
    }
}
