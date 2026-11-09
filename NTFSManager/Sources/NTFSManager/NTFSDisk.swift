import Foundation

struct NTFSDisk: Identifiable, Equatable {
    let id: String              // 分区标识，如 disk4s1
    let wholeDisk: String       // 所在整盘，如 disk4
    let name: String
    let size: Int64
    let busProtocol: String
    let mediaName: String
    let isInternal: Bool
    /// 系统自带驱动的挂载点（只读）
    let systemMountPoint: String?
    /// ntfs-3g 读写挂载点
    let rwMountPoint: String?
    var freeBytes: Int64?
    var totalBytes: Int64?

    var device: String { "/dev/\(id)" }
    var mountPoint: String? { rwMountPoint ?? systemMountPoint }

    enum State { case unmounted, readOnly, readWrite }
    var state: State {
        if rwMountPoint != nil { return .readWrite }
        if systemMountPoint != nil { return .readOnly }
        return .unmounted
    }
}
