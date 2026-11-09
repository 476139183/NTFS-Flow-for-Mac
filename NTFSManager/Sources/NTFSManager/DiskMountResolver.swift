import Foundation

struct MountedVolume {
    let path: String
    let source: String
    let type: String
    let readOnly: Bool
}

enum DiskMountResolver {
    static func normalizedLabel(_ name: String) -> String {
        String(name.unicodeScalars.filter {
            $0.value >= 32 && $0.value != 127 && !",/:".unicodeScalars.contains($0)
        }).trimmingCharacters(in: .whitespaces)
    }

    static func existingMount(device: String, label: String, labelIsUnique: Bool,
                              processOutput: String, mounts: [MountedVolume]) -> String? {
        let candidates = mounts.filter {
            !$0.readOnly && $0.type == "nfs" && $0.source.hasPrefix("fuse-t:")
        }
        let devicePattern = "(?:^|\\s)" + NSRegularExpression.escapedPattern(for: device) + "(?:\\s|$)"
        let processes = processOutput.split(separator: "\n").map(String.init).filter {
            let executable = $0.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
            return executable.hasSuffix("/ntfs-3g") || executable == "ntfs-3g"
        }.filter { $0.range(of: devicePattern, options: .regularExpression) != nil }
        let matched = candidates.filter { mount in
            let path = NSRegularExpression.escapedPattern(for: mount.path)
            let pattern = "(?:^|\\s)[\"']?" + path + "[\"']?(?=\\s+-|\\s*$)"
            return processes.contains { $0.range(of: pattern, options: .regularExpression) != nil }
        }
        if matched.count == 1 { return matched[0].path }

        // FUSE-T 挂载源保留卷名；命令行无法解析时仅对唯一卷名做匹配。
        // 不用系统只读挂载点猜测，避免把“卷名 1”当成真正的读写挂载点。
        guard labelIsUnique else { return nil }
        let matchingSources = candidates.filter { $0.source == "fuse-t:/" + normalizedLabel(label) }
        return matchingSources.count == 1 ? matchingSources[0].path : nil
    }
}
