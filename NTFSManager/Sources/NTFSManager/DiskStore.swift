import Foundation
import AppKit
import Observation

@MainActor
@Observable
final class DiskStore {
    var disks: [NTFSDisk] = []
    private var operations = DiskOperationCoordinator()
    var busy: Set<String> {
        Set(disks.filter { operations.activeDisks.contains($0.wholeDisk) }.map(\.id))
    }
    var scanError: String?
    var scanning = false
    var dependenciesInstalled = DiskService.dependenciesInstalled
    var alert: AlertInfo?
    var toast: String?
    var privilege = Privilege.status
    var privilegeBusy = false
    var installingDriver = false

    var autoMount: Bool {
        didSet { UserDefaults.standard.set(autoMount, forKey: "autoMount") }
    }

    /// 本次运行里用户手动卸载/弹出过、或自动挂载失败过的盘，不再自动挂回
    private var autoMountSkip: Set<String> = []
    private var known: Set<String> = []
    private var refreshPending = false
    private var rescanRequested = false
    private var watcher: DiskWatcher?
    private var timer: Timer?

    struct AlertInfo: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        var retryForce: NTFSDisk?
    }

    init() {
        autoMount = UserDefaults.standard.bool(forKey: "autoMount")
        watcher = DiskWatcher { [weak self] in self?.scheduleRefresh() }
        // DiskArbitration 有时漏掉 FUSE-T 的变化，加个低频兜底轮询
        timer = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        // 插盘后系统还要探测、自动挂只读，稍等一下再扫
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.refreshPending = false
            self?.refresh()
        }
    }

    func refresh() {
        guard !scanning else { rescanRequested = true; return }
        scanning = true
        dependenciesInstalled = DiskService.dependenciesInstalled
        if !privilegeBusy { privilege = Privilege.status }
        Task.detached {
            let result = Result { try DiskService.scan() }
            await MainActor.run {
                self.scanning = false
                switch result {
                case .success(let disks):
                    self.scanError = nil
                    if disks != self.disks { self.disks = disks }
                    self.handleArrivals(disks)
                case .failure(let error):
                    // 扫描失败保留最后一次有效列表，不能伪装成用户拔掉了硬盘。
                    self.scanError = error.localizedDescription
                }
                if self.rescanRequested {
                    self.rescanRequested = false
                    self.refresh()
                }
            }
        }
    }

    private func handleArrivals(_ list: [NTFSDisk]) {
        let ids = Set(list.map(\.id))
        let arrived = list.filter { !known.contains($0.id) }
        // 拔掉的盘再插回来，允许重新自动挂载
        autoMountSkip.formIntersection(ids)
        known = ids
        guard autoMount, dependenciesInstalled else { return }
        let targets = arrived.filter {
            $0.state != .readWrite && !autoMountSkip.contains($0.id) && !busy.contains($0.id)
        }
        targets.forEach { autoMountSkip.insert($0.id) }
        mountGroups(targets)
    }

    // MARK: - 操作

    func mount(_ disk: NTFSDisk, force: Bool = false) {
        perform(disk, title: "挂载失败") {
            let mp = try DiskService.mountReadWrite(disk, mode: force ? .removeHiberfile : .normal)
            return "「\(disk.name)」已读写挂载到 \(mp)"
        } onError: { [weak self] error in
            if error is HibernatedError {
                self?.alert = AlertInfo(title: "无法读写挂载", message: error.localizedDescription, retryForce: disk)
                return true
            }
            return false
        }
    }

    func unmount(_ disk: NTFSDisk) {
        autoMountSkip.insert(disk.id)
        perform(disk, title: "卸载失败") {
            try DiskService.unmount(disk)
            return "「\(disk.name)」已卸载"
        }
    }

    func restoreReadOnly(_ disk: NTFSDisk) {
        autoMountSkip.insert(disk.id)
        perform(disk, title: "切换只读失败") {
            try DiskService.unmount(disk)
            try DiskService.mountSystemReadOnly(disk)
            return "「\(disk.name)」已切回系统只读"
        }
    }

    func eject(_ disk: NTFSDisk) {
        let siblings = disks.filter { $0.wholeDisk == disk.wholeDisk && $0.id != disk.id }
        ([disk] + siblings).forEach { autoMountSkip.insert($0.id) }
        perform(disk, title: "弹出失败") {
            for sibling in siblings where sibling.mountPoint != nil { try DiskService.unmount(sibling) }
            try DiskService.eject(disk)
            return "「\(disk.name)」已安全弹出，可以拔出了"
        }
    }

    func ejectAll() {
        let wholes = Dictionary(grouping: disks, by: \.wholeDisk)
        for (_, parts) in wholes {
            parts.forEach { autoMountSkip.insert($0.id) }
            guard let first = parts.first else { continue }
            perform(first, title: "弹出失败") {
                for p in parts.dropFirst() where p.mountPoint != nil { try DiskService.unmount(p) }
                try DiskService.eject(first)
                return "已全部弹出"
            }
        }
    }

    func mountAll() {
        mountGroups(disks.filter { $0.state != .readWrite })
    }

    private func mountGroups(_ targets: [NTFSDisk]) {
        for parts in Dictionary(grouping: targets, by: \.wholeDisk).values {
            guard let first = parts.first else { continue }
            if parts.count == 1 { mount(first); continue }
            perform(first, title: "挂载失败") {
                for part in parts { _ = try DiskService.mountReadWrite(part) }
                return "已读写挂载 \(parts.count) 个分区"
            }
        }
    }

    func fix(_ disk: NTFSDisk) {
        perform(disk, title: "修复失败") {
            let out = try DiskService.fix(disk)
            try? DiskService.mountSystemReadOnly(disk)
            let last = out.split(separator: "\n").last.map(String.init) ?? ""
            return "「\(disk.name)」已清除脏卷标记。\(last)"
        }
    }

    /// 一键安装 FUSE-T + 内置 ntfs-3g
    func installDriver() {
        guard !installingDriver, !privilegeBusy, operations.activeDisks.isEmpty else { return }
        guard let script = Bundle.main.path(forResource: "install-driver", ofType: "sh"),
              let driver = Bundle.main.path(forResource: "driver", ofType: nil) else {
            alert = AlertInfo(title: "安装失败", message: "App 内缺少驱动文件，请用 build-app.sh 打包的版本")
            return
        }
        installingDriver = true
        Task.detached {
            let outcome = Result {
                try Shell.runAsRoot("/bin/bash \(Shell.quote(script)) \(Shell.quote(driver))")
            }
            await MainActor.run {
                self.installingDriver = false
                switch outcome {
                case .success:
                    self.showToast("驱动安装完成")
                    self.alert = AlertInfo(title: "驱动安装完成",
                                           message: "如果之后挂载时提示权限问题：到 系统设置 › 隐私与安全性，放行 fuse-t，并在「完全磁盘访问权限」里加入 NTFS 管理器。")
                case .failure(ShellError.cancelled):
                    break
                case .failure(let error):
                    self.alert = AlertInfo(title: "驱动安装失败", message: error.localizedDescription)
                }
                self.refresh()
            }
        }
    }

    /// 开关免密码挂载（开启/关闭时各要输一次密码）
    func setPasswordless(_ on: Bool) {
        guard !privilegeBusy, !installingDriver, operations.activeDisks.isEmpty else { return }
        privilegeBusy = true
        Task.detached {
            let outcome = Result { on ? try Privilege.enable() : try Privilege.disable() }
            await MainActor.run {
                self.privilegeBusy = false
                self.privilege = Privilege.status
                switch outcome {
                case .success:
                    self.showToast(on ? "已开启免密码挂载" : "已关闭免密码挂载")
                case .failure(ShellError.cancelled):
                    break
                case .failure(let error):
                    self.alert = AlertInfo(title: "设置免密码挂载失败", message: error.localizedDescription)
                }
            }
        }
    }

    func open(_ disk: NTFSDisk) {
        guard let mp = disk.mountPoint else { return }
        if !NSWorkspace.shared.open(URL(fileURLWithPath: mp)) {
            alert = AlertInfo(title: "无法打开磁盘", message: "请在 系统设置 › 隐私与安全性 › 文件与文件夹 中允许「NTFS 管理器」访问网络宗卷，然后重试。")
        }
    }

    // MARK: -

    private func perform(_ disk: NTFSDisk, title: String,
                         _ work: @escaping @Sendable () throws -> String,
                         onError: ((Error) -> Bool)? = nil) {
        guard !installingDriver, !privilegeBusy, operations.begin(disk.wholeDisk) else { return }
        Task.detached {
            let outcome: Result<String, Error> = Result { try work() }
            await MainActor.run {
                self.operations.finish(disk.wholeDisk)
                switch outcome {
                case .success(let msg):
                    self.showToast(msg)
                case .failure(let error):
                    if onError?(error) == true { break }
                    if case ShellError.cancelled = error { break }
                    self.alert = AlertInfo(title: title, message: error.localizedDescription)
                }
                self.refresh()
            }
        }
    }

    private func showToast(_ msg: String) {
        toast = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            if self?.toast == msg { self?.toast = nil }
        }
    }
}
