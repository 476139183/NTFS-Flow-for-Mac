import SwiftUI
import ServiceManagement

@main
struct NTFSManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = DiskStore()

    var body: some Scene {
        Window("NTFS Flow", id: "main") {
            ContentView()
                .environment(store)
        }
        .defaultSize(width: 620, height: 460)

        MenuBarExtra {
            MenuBarView()
                .environment(store)
        } label: {
            Image(systemName: store.disks.contains { $0.state == .readWrite }
                  ? "externaldrive.fill.badge.checkmark" : "externaldrive")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// `NTFSManager --list`：命令行打印扫描结果，用于排查
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard CommandLine.arguments.contains("--list") else { return }
        do {
            for d in try DiskService.scan() {
                print("\(d.device)\t\(d.name)\t\(d.state)\t\(d.size.bytesText)\t\(d.mountPoint ?? "-")")
            }
            exit(0)
        } catch {
            fputs("磁盘扫描失败：\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock 可能缓存旧的默认图标，运行时也明确使用包内图标。
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let window = sender.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
        sender.activate(ignoringOtherApps: true)
        return true
    }

    /// 关掉主窗口后继续驻留菜单栏
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

enum LoginItem {
    static var enabled: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

extension Int64 {
    var bytesText: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}
