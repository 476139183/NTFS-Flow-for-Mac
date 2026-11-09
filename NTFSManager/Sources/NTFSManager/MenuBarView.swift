import SwiftUI

struct MenuBarView: View {
    @Environment(DiskStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("NTFS 磁盘").font(.headline)
                Spacer()
                if store.scanning { ProgressView().controlSize(.mini) }
            }

            if let error = store.scanError {
                Text("扫描失败：\(error)").foregroundStyle(.orange).font(.caption)
                Button("重新扫描") { store.refresh() }.disabled(store.scanning)
            } else if store.disks.isEmpty {
                Text("未检测到 NTFS 磁盘").foregroundStyle(.secondary).font(.callout)
            }
            ForEach(store.disks) { disk in
                MenuDiskRow(disk: disk)
            }

            if let toast = store.toast {
                Text(toast).font(.caption).foregroundStyle(.secondary)
            }

            Divider()
            Toggle("插入后自动读写挂载", isOn: $store.autoMount).toggleStyle(.checkbox)
            HStack {
                Button("打开主窗口") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("全部弹出") { store.ejectAll() }.disabled(store.disks.isEmpty)
                Button("退出") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { store.refresh() }
    }
}

struct MenuDiskRow: View {
    @Environment(DiskStore.self) private var store
    let disk: NTFSDisk

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "externaldrive.fill").foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(disk.name).lineLimit(1)
                    StateBadge(state: disk.state)
                }
                if let total = disk.totalBytes, let free = disk.freeBytes {
                    Text("可用 \(free.bytesText) / \(total.bytesText)").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text(disk.size.bytesText).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if store.busy.contains(disk.id) {
                ProgressView().controlSize(.mini)
            } else {
                if disk.state != .readWrite {
                    Button("读写") { store.mount(disk) }.disabled(!store.dependenciesInstalled)
                } else {
                    Button { store.open(disk) } label: { Image(systemName: "folder") }.help("打开")
                }
                Button { store.eject(disk) } label: { Image(systemName: "eject.fill") }.help("安全弹出")
            }
        }
        .controlSize(.small)
    }
}
