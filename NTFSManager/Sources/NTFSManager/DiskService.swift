import Foundation

enum DiskService {
    static let ntfs3g = "/usr/local/bin/ntfs-3g"
    static let diskutil = "/usr/sbin/diskutil"

    static var dependenciesInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: ntfs3g)
            && FileManager.default.fileExists(atPath: "/Library/Application Support/fuse-t")
    }

    // MARK: - 扫描

    static func scan() throws -> [NTFSDisk] {
        let data = try Shell.checkedData(diskutil, ["list", "-plist"])
        let all = try decodeDiskList(data)

        var candidates: [String] = []
        for disk in all where disk["APFSVolumes"] == nil {
            let parts = disk["Partitions"] as? [[String: Any]] ?? []
            let entries = parts.isEmpty ? [disk] : parts   // 无分区表时整盘就是卷
            for entry in entries {
                let content = entry["Content"] as? String ?? ""
                if content.hasPrefix("Apple_") || content == "EFI" || content.contains("APFS") { continue }
                if let id = entry["DeviceIdentifier"] as? String { candidates.append(id) }
            }
        }

        var infos = [Result<[String: Any], Error>?](repeating: nil, count: candidates.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: candidates.count) { i in
            let info = Result { try diskInfo(candidates[i]) }
            lock.lock(); infos[i] = info; lock.unlock()
        }

        let resolvedInfos = try infos.compactMap { try $0?.get() }
        let rwMounts = ntfs3gMounts(infos: resolvedInfos)
        return resolvedInfos.compactMap { info -> NTFSDisk? in
            guard (info["FilesystemType"] as? String) == "ntfs" || (info["Content"] as? String) == "Windows_NTFS",
                  let id = info["DeviceIdentifier"] as? String
            else { return nil }
            let sysMP = (info["MountPoint"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            var disk = NTFSDisk(
                id: id,
                wholeDisk: info["ParentWholeDisk"] as? String ?? id,
                name: (info["VolumeName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id,
                size: (info["TotalSize"] as? NSNumber)?.int64Value ?? (info["Size"] as? NSNumber)?.int64Value ?? 0,
                busProtocol: info["BusProtocol"] as? String ?? "",
                mediaName: info["MediaName"] as? String ?? "",
                isInternal: info["Internal"] as? Bool ?? false,
                systemMountPoint: sysMP,
                rwMountPoint: rwMounts["/dev/\(id)"]
            )
            // 只读系统元数据；后台扫描不打开网络卷，避免反复触发文件访问授权。
            disk.freeBytes = (info["VolumeFreeSpace"] as? NSNumber)?.int64Value
            disk.totalBytes = (info["VolumeSize"] as? NSNumber)?.int64Value
                ?? (info["TotalSize"] as? NSNumber)?.int64Value
            if let path = disk.mountPoint, let capacity = cachedCapacity(path) {
                disk.totalBytes = capacity.total
                disk.freeBytes = capacity.free
            }
            return disk
        }
        .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    static func decodeDiskList(_ data: Data) throws -> [[String: Any]] {
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dictionary = plist as? [String: Any],
              let disks = dictionary["AllDisksAndPartitions"] as? [[String: Any]] else {
            throw ShellError.failed("系统返回的磁盘列表格式异常，请刷新重试。")
        }
        return disks
    }

    static func diskInfo(_ id: String) throws -> [String: Any] {
        let data = try Shell.checkedData(diskutil, ["info", "-plist", id])
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw ShellError.failed("无法解析磁盘 \(id) 的信息。")
        }
        return info
    }

    /// 结合进程参数和内核挂载表识别 FUSE-T，不依赖参数顺序或系统只读挂载点。
    static func ntfs3gMounts(infos: [[String: Any]]) -> [String: String] {
        let ps = Shell.run("/bin/ps", ["-axww", "-o", "command="])
        let mounts = mountEntries().map { entry -> MountedVolume in
            var entry = entry
            let source = withUnsafePointer(to: &entry.f_mntfromname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            let type = withUnsafePointer(to: &entry.f_fstypename) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSNAMELEN)) { String(cString: $0) }
            }
            return MountedVolume(path: mountPath(entry), source: source, type: type,
                                 readOnly: entry.f_flags & UInt32(MNT_RDONLY) != 0)
        }
        let ntfsInfos = infos.filter {
            ($0["FilesystemType"] as? String) == "ntfs" || ($0["Content"] as? String) == "Windows_NTFS"
        }
        let labels = ntfsInfos.compactMap { $0["VolumeName"] as? String }.map(DiskMountResolver.normalizedLabel)
        var result: [String: String] = [:]
        for info in ntfsInfos {
            guard let id = info["DeviceIdentifier"] as? String else { continue }
            let label = info["VolumeName"] as? String ?? "NTFS-\(id)"
            let normalized = DiskMountResolver.normalizedLabel(label)
            let unique = labels.filter { $0 == normalized }.count == 1
            if let path = DiskMountResolver.existingMount(device: "/dev/\(id)", label: label,
                labelIsUnique: unique, processOutput: ps.ok ? ps.output : "", mounts: mounts) {
                result["/dev/\(id)"] = path
            }
        }
        return result
    }

    static func isMountPoint(_ path: String) -> Bool {
        mountEntries().contains { mountPath($0) == path }
    }

    static func cachedCapacity(_ path: String) -> (total: Int64, free: Int64)? {
        guard let entry = mountEntries().first(where: { mountPath($0) == path }),
              entry.f_bsize > 0, entry.f_blocks > 0 else { return nil }
        let total = entry.f_blocks.multipliedReportingOverflow(by: UInt64(entry.f_bsize))
        let free = entry.f_bavail.multipliedReportingOverflow(by: UInt64(entry.f_bsize))
        guard !total.overflow, !free.overflow,
              let totalBytes = Int64(exactly: total.partialValue),
              let freeBytes = Int64(exactly: free.partialValue) else { return nil }
        return (totalBytes, freeBytes)
    }

    private static func mountPath(_ value: statfs) -> String {
        var entry = value
        return withUnsafePointer(to: &entry.f_mntonname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
    }

    private static func mountEntries() -> [statfs] {
        // MNT_NOWAIT 读取内核缓存，不对网络卷发起文件访问或符号链接解析。
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0 else { return [] }
        // 每次调用独立的缓冲区，避免 getmntinfo 共享缓冲区的并发访问问题。
        var entries: [statfs] = Array(repeating: statfs(), count: Int(count) + 8)
        let actualCount = entries.withUnsafeMutableBufferPointer { buffer in
            getfsstat(buffer.baseAddress, Int32(buffer.count * MemoryLayout<statfs>.stride), MNT_NOWAIT)
        }
        guard actualCount > 0 else { return [] }
        return Array(entries.prefix(Int(actualCount)))
    }

    // MARK: - 操作

    enum MountMode { case normal, removeHiberfile }

    /// 读写挂载：由特权助手卸掉系统只读挂载 → ntfs-3g 挂到 /Volumes/<卷名>（Finder 侧边栏可见）
    static func mountReadWrite(_ disk: NTFSDisk, mode: MountMode = .normal) throws -> String {
        guard let current = try scan().first(where: { $0.id == disk.id }) else {
            throw ShellError.failed("磁盘已断开，请刷新列表后重试。")
        }
        if let mp = current.rwMountPoint { return mp }
        let out: String
        do {
            out = try Privilege.runHelper(["mount", disk.id] + (mode == .removeHiberfile ? ["force"] : []))
        } catch {
            // 可能是另一个挂载请求刚刚成功，先重新核对，不能再创建系统只读副本。
            if let current = try? scan().first(where: { $0.id == disk.id }), let mp = current.rwMountPoint {
                return mp
            }
            if case ShellError.failed(let raw) = error, raw.contains("已被 ntfs-3g 挂载") {
                throw ShellError.failed("ntfs-3g 进程已存在，但尚未确认其有效挂载点。请刷新后重试；为避免冲突，没有重复挂载。\n\n\(raw)")
            }
            Shell.run(diskutil, ["mount", disk.device])
            throw explain(error)
        }
        guard let mp = out.split(separator: "\n").last.map(String.init), mp.hasPrefix("/Volumes/") else {
            throw ShellError.failed("助手返回异常：\(out)")
        }
        // FUSE-T 挂载生效有一点延迟
        for _ in 0..<20 where !isMountPoint(mp) { Thread.sleep(forTimeInterval: 0.25) }
        guard isMountPoint(mp) else {
            Shell.run(diskutil, ["mount", disk.device])
            throw ShellError.failed("ntfs-3g 已执行但挂载点未生效。请到 系统设置 › 隐私与安全性 里确认已放行 fuse-t。")
        }
        return mp
    }

    static func unmount(_ disk: NTFSDisk) throws {
        if let mp = disk.rwMountPoint {
            _ = try Privilege.runHelper(["unmount", mp])
            for _ in 0..<12 where isMountPoint(mp) { Thread.sleep(forTimeInterval: 0.25) }
            if isMountPoint(mp) { throw ShellError.failed("卸载失败，可能有程序正在使用 \(mp)") }
        } else if disk.systemMountPoint != nil {
            let r = Shell.run(diskutil, ["unmount", disk.device])
            if !r.ok { throw ShellError.failed(r.output) }
        }
    }

    static func eject(_ disk: NTFSDisk) throws {
        try unmount(disk)
        let r = Shell.run(diskutil, ["eject", disk.wholeDisk])
        if !r.ok { throw ShellError.failed("弹出失败：\(r.output)") }
    }

    /// 清除脏卷标记（Windows 未正常关机 / chkdsk 待处理）
    static func fix(_ disk: NTFSDisk) throws -> String {
        if disk.mountPoint != nil { try unmount(disk) }
        return try Privilege.runHelper(["fix", disk.id])
    }

    static func mountSystemReadOnly(_ disk: NTFSDisk) throws {
        let r = Shell.run(diskutil, ["mount", disk.device])
        if !r.ok { throw ShellError.failed(r.output) }
    }

    // MARK: - 辅助

    /// 把 ntfs-3g 常见报错翻译成人话
    static func explain(_ error: Error) -> Error {
        DiskErrorClassifier.explain(error)
    }
}
