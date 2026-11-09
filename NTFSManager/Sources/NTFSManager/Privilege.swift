import Foundation

/// 所有需要 root 的操作都经过 ntfs-manager-helper：
/// - 已开启免密：`sudo -n` 调用装在 /Library/PrivilegedHelperTools 的助手（sudoers 只放行这一个文件）
/// - 未开启：用系统管理员密码框以 root 运行 App 内自带的助手
enum Privilege {
    static let installedHelper = "/Library/PrivilegedHelperTools/ntfs-manager-helper"
    static let sudoersFile = "/etc/sudoers.d/ntfs-manager"

    static var bundledHelper: String? {
        Bundle.main.path(forResource: "ntfs-manager-helper", ofType: nil)
    }

    enum Status: Equatable {
        case disabled
        case enabled
        /// App 更新后自带助手与已安装的不一致，需要重新开启一次
        case outdated
    }

    static var status: Status {
        let fm = FileManager.default
        guard fm.fileExists(atPath: installedHelper), fm.fileExists(atPath: sudoersFile) else { return .disabled }
        guard let bundled = bundledHelper,
              fm.contentsEqual(atPath: bundled, andPath: installedHelper) else { return .outdated }
        return .enabled
    }

    /// 以 root 运行助手，返回其输出
    static func runHelper(_ args: [String]) throws -> String {
        if status == .enabled {
            let r = Shell.runDetached("/usr/bin/sudo", ["-n", installedHelper] + args)
            // sudoers 被外部改掉等情况：退回密码框
            if !(r.output.contains("password is required") || r.output.contains("需要密码")) {
                guard r.ok else { throw ShellError.failed(r.output.trimmingCharacters(in: .whitespacesAndNewlines)) }
                return r.output
            }
        }
        guard let helper = bundledHelper else {
            throw ShellError.failed("找不到内置助手，请用 build-app.sh 打包后再运行")
        }
        let cmd = ([helper] + args).map(Shell.quote).joined(separator: " ")
        return try Shell.runAsRoot(cmd)
    }

    /// 开启免密：安装助手 + 写 sudoers 规则（visudo 校验通过才生效）
    static func enable() throws {
        guard let helper = bundledHelper else { throw ShellError.failed("找不到内置助手，请用 build-app.sh 打包后再运行") }
        let user = NSUserName()
        guard user.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else {
            throw ShellError.failed("用户名含特殊字符，无法写入 sudoers：\(user)")
        }
        let q = Shell.quote
        let rule = "\(user) ALL=(root) NOPASSWD: \(installedHelper)"
        // 临时文件名带点：sudo 的 includedir 会忽略含 . 的文件，校验前不会生效
        let tmp = "/etc/sudoers.d/.ntfs-manager.tmp"
        let script = """
        /usr/bin/install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools && \
        /usr/bin/install -o root -g wheel -m 755 \(q(helper)) \(q(installedHelper)) && \
        /bin/rm -f \(tmp) && \
        /usr/bin/printf '%s\\n' \(q(rule)) > \(tmp) && \
        /usr/sbin/chown root:wheel \(tmp) && /bin/chmod 440 \(tmp) && \
        /usr/sbin/visudo -cf \(tmp) && /bin/mv -f \(tmp) \(q(sudoersFile)) \
        || { /bin/rm -f \(tmp); exit 1; }
        """
        _ = try Shell.runAsRoot(script)
        guard status == .enabled else { throw ShellError.failed("安装后校验失败，请重试") }
    }

    static func disable() throws {
        _ = try Shell.runAsRoot("/bin/rm -f \(Shell.quote(sudoersFile)) \(Shell.quote(installedHelper))")
    }
}
