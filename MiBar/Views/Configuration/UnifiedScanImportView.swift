import AppKit
import SwiftUI

/// 米家扫码快速导入与设备候选选择组件
/// 展示授权二维码，并在扫码成功后呈现账号下所有可用设备供用户自主选择添加。
struct UnifiedScanImportView: View {
    @Bindable var store: LightStore
    @Bindable var thermometerStore: ThermometerStore
    let canGoBack: Bool
    let onBack: () -> Void
    let onDeviceAdded: () -> Void

    @State private var isBackHovered = false

    private var hasDiscoveredItems: Bool {
        !store.cloudDevices.isEmpty || !store.scannedCloudThermometers.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            // MARK: - Header Bar
            headerBar

            // MARK: - QR Code View
            qrCodeSection

            // MARK: - Login Status
            loginStatusSection

            // MARK: - Candidates Selection List
            if hasDiscoveredItems {
                candidatesSelectionList
            }

            // MARK: - Bottom Actions
            bottomActionSection
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 8) {
            if canGoBack {
                Button {
                    withAnimation {
                        onBack()
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

            if canGoBack {
                Color.clear.frame(width: 70, height: 32)
            }
        }
    }

    // MARK: - QR Code Section

    @ViewBuilder
    private var qrCodeSection: some View {
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
    }

    // MARK: - Login Status Section

    @ViewBuilder
    private var loginStatusSection: some View {
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
    }

    // MARK: - Candidates Selection List

    private var candidatesSelectionList: some View {
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
                            .lineLimit(1)
                        Text(light.localIP.isEmpty ? "由米家云端提供" : light.localIP)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
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
                                withAnimation { onDeviceAdded() }
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
                                .lineLimit(1)
                            Text(record.modelType.shortName)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        Text("MAC: \(record.formattedMAC)")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if isAdded {
                        Text("已添加")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else {
                        Button("添加") {
                            thermometerStore.addFromCloudRecord(record)
                            withAnimation { onDeviceAdded() }
                        }
                        .buttonStyle(MiBarPrimaryButtonStyle())
                        .controlSize(.small)
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            }

            if canGoBack {
                Button {
                    withAnimation { onBack() }
                } label: {
                    Text("进入列表")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MiBarSecondaryButtonStyle())
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Bottom Action Section

    private var bottomActionSection: some View {
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

                Button("取消") {
                    store.cancelCloudQRLogin()
                }
                .buttonStyle(MiBarSecondaryButtonStyle())
                .frame(maxWidth: store.qrLoginURL != nil ? 64 : .infinity)
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
