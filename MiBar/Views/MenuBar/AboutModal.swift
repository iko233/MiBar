import SwiftUI
import AppKit

/// 关于 MiBar 弹窗视图
struct AboutModal: View {
    let onDismiss: () -> Void

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .background(.ultraThinMaterial.opacity(0.6))
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
                .accessibilityLabel("关闭关于窗口")

            VStack(spacing: 16) {
                // Header: App Icon + Name + Version
                VStack(spacing: 8) {
                    if let appIcon = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage {
                        Image(nsImage: appIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                    } else {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 56, height: 56)
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white)
                        }
                    }

                    VStack(spacing: 2) {
                        Text("MiBar")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)

                        Text(appVersion)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }

                // Description
                VStack(spacing: 6) {
                    Text("专为 macOS 设计的米家智能显示器挂灯 1S 控制工具")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("支持局域网 miIO 本地直连 · 扫码一键配对 · 色温亮度精细控制")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 8)

                Divider()
                    .opacity(0.2)

                // Links & Copyright
                VStack(spacing: 8) {
                    HStack(spacing: 16) {
                        Button {
                            if let url = URL(string: "https://mibar.pages.dev/") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "safari")
                                    .font(.system(size: 10.5, weight: .medium))
                                Text("官方网站")
                                    .font(.system(size: 11, weight: .medium))
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 8, weight: .semibold))
                            }
                            .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)

                        Button {
                            if let url = URL(string: "https://github.com/extrastu/MiBar") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "link")
                                    .font(.system(size: 10.5, weight: .medium))
                                Text("GitHub 仓库")
                                    .font(.system(size: 11, weight: .medium))
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 8, weight: .semibold))
                            }
                            .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("MIT License · Copyright © 2026 extrastu")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }

                // Close button
                Button("完成", action: onDismiss)
                    .buttonStyle(MiBarPrimaryButtonStyle())
                    .frame(height: 32)
                    .padding(.top, 2)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.35), .white.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .padding(20)
            .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityAddTraits(.isModal)
        .accessibilityElement(children: .contain)
    }
}
