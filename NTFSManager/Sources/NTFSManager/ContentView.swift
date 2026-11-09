import SwiftUI

struct ContentView: View {
    @Environment(DiskStore.self) private var store
    @State private var launchAtLogin = LoginItem.enabled

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            if !store.dependenciesInstalled { DependencyBanner() }
            if let error = store.scanError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("磁盘扫描失败，显示上次结果").bold()
                        Text(error).font(.caption).textSelection(.enabled)
                    }
                    Spacer()
                    Button("重试") { store.refresh() }.disabled(store.scanning)
                }
                .padding(12)
                .background(.orange.opacity(0.12))
            }

            if store.disks.isEmpty && store.scanError != nil {
                ContentUnavailableView("暂时无法读取磁盘列表", systemImage: "externaldrive.badge.exclamationmark",
                                       description: Text("请检查连接和系统权限，再点击重试。"))
                    .frame(maxHeight: .infinity)
            } else if store.disks.isEmpty {
                ContentUnavailableView {
                    Label("没有检测到 NTFS 磁盘", systemImage: "externaldrive.badge.questionmark")
                } description: {
                    Text("插入 Windows 格式（NTFS）的硬盘或 U 盘，会自动出现在这里。")
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(store.disks) { DiskCard(disk: $0) }
                    }
                    .padding(16)
                }
            }

            Divider()
            HStack(spacing: 16) {
                Toggle("插入后自动读写挂载", isOn: $store.autoMount)
                PasswordlessToggle()
                Toggle("登录时启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { try LoginItem.set(on) } catch {
                            launchAtLogin = LoginItem.enabled
                            store.alert = .init(title: "设置失败", message: error.localizedDescription)
                        }
                    }
                Spacer()
                if let toast = store.toast {
                    Text(toast).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        .transition(.opacity)
                }
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .animation(.default, value: store.toast)
        }
        .frame(minWidth: 560, minHeight: 360)
        .toolbar {
            ToolbarItemGroup {
                if store.scanning { ProgressView().controlSize(.small) }
                Button { store.refresh() } label: { Label("刷新", systemImage: "arrow.clockwise") }
                    .keyboardShortcut("r")
                Menu {
                    Button("全部读写挂载") { store.mountAll() }
                    Button("全部弹出") { store.ejectAll() }
                } label: { Label("全部", systemImage: "square.stack.3d.up") }
                    .disabled(store.disks.isEmpty)
            }
        }
        .alert(item: $store.alert) { info in
            if let disk = info.retryForce {
                Alert(title: Text(info.title), message: Text(info.message),
                      primaryButton: .destructive(Text("强制挂载")) { store.mount(disk, force: true) },
                      secondaryButton: .cancel(Text("取消")))
            } else {
                Alert(title: Text(info.title), message: Text(info.message))
            }
        }
    }
}

struct PasswordlessToggle: View {
    @Environment(DiskStore.self) private var store

    var body: some View {
        HStack(spacing: 4) {
            Toggle("免密码挂载", isOn: Binding(
                get: { store.privilege != .disabled },
                set: { store.setPasswordless($0) }
            ))
            .disabled(store.privilegeBusy)
            .help("安装一个只能挂载/卸载/修复 NTFS 盘的 root 助手，并在 sudoers 里只放行它。之后挂载不再弹密码框。")
            if store.privilegeBusy {
                ProgressView().controlSize(.mini)
            } else if store.privilege == .outdated {
                Button("更新助手") { store.setPasswordless(true) }
                    .controlSize(.small)
                    .help("App 已更新，已安装的助手是旧版本。更新前会继续弹密码框。")
            }
        }
    }
}

struct DependencyBanner: View {
    @Environment(DiskStore.self) private var store

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("还没安装 NTFS 读写驱动，现在只能只读").bold()
                Text("一键安装 FUSE-T（从官方下载并校验签名）和内置的 ntfs-3g，需要联网，会要求输入一次密码。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if store.installingDriver {
                ProgressView().controlSize(.small)
                Text("安装中…").font(.callout)
            } else {
                Button("一键安装驱动") { store.installDriver() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(.orange.opacity(0.12))
    }
}

struct DiskCard: View {
    @Environment(DiskStore.self) private var store
    let disk: NTFSDisk

    var body: some View {
        let busy = store.busy.contains(disk.id)
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: disk.isInternal ? "internaldrive" : "externaldrive.fill")
                .font(.system(size: 30))
                .foregroundStyle(.tint)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(disk.name).font(.headline)
                    StateBadge(state: disk.state)
                }
                Text([disk.device, disk.busProtocol, disk.size.bytesText]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)

                if let total = disk.totalBytes, let free = disk.freeBytes, total > 0 {
                    ProgressView(value: Double(total - free), total: Double(total))
                        .tint(Double(free) / Double(total) < 0.1 ? .red : .accentColor)
                    Text("已用 \((total - free).bytesText)，可用 \(free.bytesText)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if let mp = disk.mountPoint {
                    Text(mp).font(.caption2.monospaced()).foregroundStyle(.tertiary).textSelection(.enabled)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                if busy {
                    ProgressView().controlSize(.small).frame(height: 22)
                } else {
                    HStack(spacing: 6) {
                        if disk.state != .readWrite {
                            Button("读写挂载") { store.mount(disk) }
                                .buttonStyle(.borderedProminent)
                                .disabled(!store.dependenciesInstalled)
                        }
                        if disk.mountPoint != nil {
                            Button("打开") { store.open(disk) }
                        }
                        Button { store.eject(disk) } label: { Image(systemName: "eject.fill") }
                            .help("安全弹出")
                    }
                    DiskMenu(disk: disk)
                }
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .contextMenu { DiskMenuItems(disk: disk) }
    }
}

struct DiskMenu: View {
    let disk: NTFSDisk
    var body: some View {
        Menu("更多") { DiskMenuItems(disk: disk) }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .font(.caption)
    }
}

struct DiskMenuItems: View {
    @Environment(DiskStore.self) private var store
    let disk: NTFSDisk

    var body: some View {
        if disk.state != .readWrite {
            Button("读写挂载") { store.mount(disk) }
        }
        if disk.state == .readWrite {
            Button("切回系统只读") { store.restoreReadOnly(disk) }
        }
        if disk.mountPoint != nil {
            Button("在 Finder 中打开") { store.open(disk) }
            Button("卸载（不弹出）") { store.unmount(disk) }
        }
        Divider()
        Button("修复脏卷标记 (ntfsfix)…") { store.fix(disk) }
        Button("复制设备路径") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(disk.device, forType: .string)
        }
        Divider()
        Button("安全弹出") { store.eject(disk) }
    }
}

struct StateBadge: View {
    let state: NTFSDisk.State
    var body: some View {
        let (text, color): (String, Color) = switch state {
        case .readWrite: ("读写", .green)
        case .readOnly: ("只读", .orange)
        case .unmounted: ("未挂载", .gray)
        }
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}
