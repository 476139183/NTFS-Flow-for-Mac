import Foundation

struct ShellResult {
    let status: Int32
    let output: String
    var ok: Bool { status == 0 }
}

enum ShellError: LocalizedError {
    case failed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .failed(let msg): return msg
        case .cancelled: return "已取消授权"
        }
    }
}

enum Shell {
    /// 所有输出落盘，避免后台子进程继承管道后导致 EOF 永不到达。
    @discardableResult
    static func run(_ path: String, _ args: [String], timeout: TimeInterval? = 30) -> ShellResult {
        execute(path, args, mergeError: true, timeout: timeout).result
    }

    static func runData(_ path: String, _ args: [String]) -> Data? {
        try? checkedData(path, args)
    }

    static func checkedData(_ path: String, _ args: [String]) throws -> Data {
        let execution = execute(path, args, mergeError: false, timeout: 30)
        guard execution.result.ok else {
            throw ShellError.failed(execution.result.output)
        }
        return execution.data
    }

    /// 特权修改不自动超时，避免只杀死 sudo 而让 root 操作继续执行。
    static func runDetached(_ path: String, _ args: [String]) -> ShellResult {
        run(path, args, timeout: nil)
    }

    private static func execute(_ path: String, _ args: [String], mergeError: Bool,
                                timeout: TimeInterval?) -> (result: ShellResult, data: Data) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ntfs-command-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
        } catch {
            return (ShellResult(status: -1, output: error.localizedDescription), Data())
        }
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("stdout")
        let errorURL = mergeError ? outputURL : directory.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        if !mergeError { FileManager.default.createFile(atPath: errorURL.path, contents: nil) }
        guard let output = try? FileHandle(forWritingTo: outputURL),
              let errors = mergeError ? output : try? FileHandle(forWritingTo: errorURL) else {
            return (ShellResult(status: -1, output: "无法创建命令输出文件"), Data())
        }
        defer {
            try? output.close()
            if !mergeError { try? errors.close() }
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors
        let completed = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completed.signal() }
        do { try process.run() } catch {
            return (ShellResult(status: -1, output: error.localizedDescription), Data())
        }
        let deadline = timeout.map { DispatchTime.now() + $0 } ?? .distantFuture
        let timedOut = completed.wait(timeout: deadline) == .timedOut
        if timedOut {
            process.terminate()
            if completed.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = completed.wait(timeout: .now() + 1)
            }
        }
        let data = (try? Data(contentsOf: outputURL)) ?? Data()
        let errorData = mergeError ? data : ((try? Data(contentsOf: errorURL)) ?? Data())
        if timedOut {
            return (ShellResult(status: -2, output: "命令执行超时，请检查磁盘连接后重试。"), data)
        }
        return (ShellResult(status: process.terminationStatus,
                            output: String(decoding: errorData, as: UTF8.self)), data)
    }

    /// shell 单引号转义
    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// 以 root 运行一段 shell 脚本，弹系统管理员密码框。
    /// 输出重定向到临时文件：ntfs-3g 会 fork 守护进程，直接接管道会让调用方一直等不到 EOF。
    static func runAsRoot(_ script: String) throws -> String {
        let log = FileManager.default.temporaryDirectory
            .appendingPathComponent("ntfs-manager-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: log) }
        let wrapped = "{ \(script) ; } > \(quote(log.path)) 2>&1 < /dev/null"
        let escaped = wrapped
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let apple = "do shell script \"\(escaped)\" with administrator privileges with prompt \"NTFS 管理器需要管理员权限来挂载或卸载磁盘\""
        let result = run("/usr/bin/osascript", ["-e", apple], timeout: nil)
        let output = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        if !result.ok {
            if result.output.contains("-128") { throw ShellError.cancelled }
            let msg = output.isEmpty ? result.output : output
            throw ShellError.failed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }
}
