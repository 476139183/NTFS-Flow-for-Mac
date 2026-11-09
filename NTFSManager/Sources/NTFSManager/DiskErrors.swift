import Foundation

/// 先判断实际失败原因，再处理驱动附带的通用 Windows 建议。
enum DiskErrorClassifier {
    static func explain(_ error: Error) -> Error {
        guard case ShellError.failed(let raw) = error else { return error }
        let lower = raw.lowercased()
        if lower.contains("operation not permitted") || lower.contains("permission denied") {
            return ShellError.failed("macOS 拦截了磁盘访问。请检查 系统设置 › 隐私与安全性：在「文件与文件夹」中允许网络宗卷访问；若原始磁盘设备访问被拒绝，再为「NTFS Flow」开启「完全磁盘访问权限」。\n\n\(raw)")
        }
        if lower.contains("input/output error") || lower.contains("i/o error") {
            return ShellError.failed("磁盘读写发生 I/O 错误，请检查连接线、供电和磁盘状态。\n\n\(raw)")
        }
        // “no hibernation or fast restarting”只是建议，不是确认休眠的证据。
        if lower.contains("windows is hibernated") || lower.contains("volume is hibernated")
            || lower.contains("hibernated volume") || lower.contains("hibernation file is present") {
            return HibernatedError(detail: raw)
        }
        if lower.contains("unsafe state") || lower.contains("unclean") || lower.contains("windows cache") {
            return ShellError.failed("NTFS 卷未处于安全关闭状态。请回到 Windows 完整关机后重试，或保持只读访问；这条错误不能确认磁盘处于休眠状态。\n\n\(raw)")
        }
        if lower.contains("busy") {
            return ShellError.failed("磁盘正被占用，请关闭正在使用它的程序后重试。\n\n\(raw)")
        }
        return ShellError.failed(raw)
    }
}

/// 仅明确报告休眠的错误才提供删除休眠文件选项。
struct HibernatedError: LocalizedError {
    let detail: String
    var errorDescription: String? {
        "这块盘在 Windows 上处于休眠或「快速启动」状态，ntfs-3g 为保护数据拒绝读写挂载。\n\n" +
        "最稳妥：插回 Windows，彻底关机（按住 Shift 点关机）或关闭快速启动。\n" +
        "也可以在这里「强制挂载」：会删除休眠文件，Windows 里未保存的会话内容将丢失。\n\n\(detail)"
    }
}
