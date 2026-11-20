import Foundation
#if canImport(Darwin)
import Darwin
#endif

enum ToolBox {

    static let maxOutput = 12000

    static var schema: [[String: Any]] {
        return [
            fn("shell", "执行一条 shell 命令（越狱/TrollStore 版可直接跑；否则走远程 runner）。返回 stdout/stderr。",
               ["cmd": ["type": "string", "description": "完整命令，非交互式"]], ["cmd"]),
            fn("read", "按行读取文本文件，带行号。",
               ["path": ["type": "string"],
                "offset": ["type": "integer", "description": "起始行，默认 1"],
                "limit": ["type": "integer", "description": "读多少行，默认 400"]], ["path"]),
            fn("write", "整体写入/新建文件（只在新建或必须整体重写时用）。",
               ["path": ["type": "string"], "content": ["type": "string"]], ["path", "content"]),
            fn("edit", "精确字符串替换改文件，old 必须与文件内容逐字符一致。",
               ["path": ["type": "string"], "old": ["type": "string"], "new": ["type": "string"]],
               ["path", "old", "new"]),
            fn("ls", "列目录。", ["path": ["type": "string", "description": "默认 ."]], []),
            fn("glob", "按通配符找文件，如 **/*.swift。",
               ["pattern": ["type": "string"], "path": ["type": "string"]], ["pattern"]),
            fn("grep", "按正则搜索文件内容，返回 路径:行号: 内容。",
               ["pattern": ["type": "string"], "path": ["type": "string"]], ["pattern"]),
            fn("http_get", "发一个 GET 请求，返回状态码与响应体。",
               ["url": ["type": "string"]], ["url"]),
            fn("done", "任务完成时调用，汇报改了什么、验证结果。",
               ["summary": ["type": "string"]], ["summary"])
        ]
    }

    private static func fn(_ name: String, _ desc: String,
                           _ props: [String: Any], _ required: [String]) -> [String: Any] {
        // Responses API 的工具是扁平结构（不像 chat/completions 里再套一层 function）
        return ["type": "function",
                "name": name,
                "description": desc,
                "parameters": ["type": "object", "properties": props, "required": required]]
    }

    // MARK: - 路径

    static var root: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return d ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    static func resolve(_ path: String) -> URL? {
        let p = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty { return root }
        if p.hasPrefix("/") {
            if Prefs.allowSystemPaths { return URL(fileURLWithPath: p) }
            return root.appendingPathComponent(String(p.drop(while: { $0 == "/" })))
        }
        return root.appendingPathComponent(p)
    }

    static func clip(_ s: String) -> String {
        if s.count <= maxOutput { return s }
        return String(s.prefix(maxOutput)) + "\n...[截断，共 \(s.count) 字符]"
    }

    // MARK: - 分发

    static func run(name: String, args: [String: Any]) async -> String {
        switch name {
        case "shell":
            return await shell(str(args["cmd"]))
        case "read":
            return readFile(str(args["path"]), offset: int(args["offset"], 1), limit: int(args["limit"], 400))
        case "write":
            return writeFile(str(args["path"]), content: str(args["content"]))
        case "edit":
            return editFile(str(args["path"]), old: str(args["old"]), new: str(args["new"]))
        case "ls":
            return listDir(str(args["path"], "."))
        case "glob":
            return globFiles(str(args["pattern"], "*"), path: str(args["path"], "."))
        case "grep":
            return grepFiles(str(args["pattern"]), path: str(args["path"], "."))
        case "http_get":
            return await httpGet(str(args["url"]))
        case "done":
            return "TASK_DONE: " + str(args["summary"])
        default:
            return "未知工具：\(name)"
        }
    }

    private static func str(_ v: Any?, _ def: String = "") -> String {
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return def
    }

    private static func int(_ v: Any?, _ def: Int) -> Int {
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String, let n = Int(s) { return n }
        return def
    }

    // MARK: - 文件

    static func readFile(_ path: String, offset: Int, limit: Int) -> String {
        guard let url = resolve(path) else { return "路径不合法" }
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return "读不到文件：\(url.path)"
        }
        let lines = text.components(separatedBy: "\n")
        let start = max(0, offset - 1)
        let end = min(lines.count, start + max(1, limit))
        guard start < lines.count else { return "文件只有 \(lines.count) 行" }
        var out = "=== \(url.path) (\(lines.count) 行) ===\n"
        for i in start..<end {
            out += String(format: "%5d| %@\n", i + 1, lines[i])
        }
        if end < lines.count { out += "...还有 \(lines.count - end) 行" }
        return clip(out)
    }

    static func writeFile(_ path: String, content: String) -> String {
        guard let url = resolve(path) else { return "路径不合法" }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
            return "已写入 \(url.path)（\(content.utf8.count) 字节）"
        } catch {
            return "写入失败：\(error.localizedDescription)"
        }
    }

    static func editFile(_ path: String, old: String, new: String) -> String {
        guard let url = resolve(path) else { return "路径不合法" }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "读不到文件：\(url.path)"
        }
        guard !old.isEmpty else { return "old 不能为空" }
        guard let range = text.range(of: old) else {
            return "未找到匹配片段（缩进/换行必须完全一致）。文件前 600 字符：\n" + String(text.prefix(600))
        }
        let updated = text.replacingCharacters(in: range, with: new)
        do {
            try updated.write(to: url, atomically: true, encoding: .utf8)
            return "已替换 1 处 → \(url.path)"
        } catch {
            return "写入失败：\(error.localizedDescription)"
        }
    }

    static func listDir(_ path: String) -> String {
        guard let url = resolve(path) else { return "路径不合法" }
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
            return "列目录失败：\(url.path)"
        }
        var out = "=== \(url.path) ===\n"
        for name in items.sorted().prefix(300) {
            let full = url.appendingPathComponent(name)
            var isDir: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: full.path, isDirectory: &isDir)
            var size = 0
            if let attrs = try? FileManager.default.attributesOfItem(atPath: full.path),
               let n = attrs[.size] as? Int {
                size = n
            }
            out += "\(name)\(isDir.boolValue ? "/" : "")  \(size)\n"
        }
        return clip(out)
    }

    static func globFiles(_ pattern: String, path: String) -> String {
        guard let base = resolve(path) else { return "路径不合法" }
        let regex = globToRegex(pattern)
        var hits: [String] = []
        if let en = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) {
            for case let f as URL in en {
                let rel = f.path.replacingOccurrences(of: base.path + "/", with: "")
                if regex.numberOfMatches(in: rel, range: NSRange(location: 0, length: rel.utf16.count)) > 0 {
                    hits.append(f.path)
                    if hits.count >= 300 { break }
                }
            }
        }
        return clip(hits.isEmpty ? "无匹配" : hits.joined(separator: "\n"))
    }

    private static func globToRegex(_ pattern: String) -> NSRegularExpression {
        var p = pattern
        p = p.replacingOccurrences(of: ".", with: "\\.")
        p = p.replacingOccurrences(of: "**/", with: "___ANY___")
        p = p.replacingOccurrences(of: "*", with: "[^/]*")
        p = p.replacingOccurrences(of: "___ANY___", with: ".*")
        p = p.replacingOccurrences(of: "?", with: ".")
        return (try? NSRegularExpression(pattern: "^" + p + "$")) ?? (try! NSRegularExpression(pattern: ".*"))
    }

    static func grepFiles(_ pattern: String, path: String) -> String {
        guard let base = resolve(path) else { return "路径不合法" }
        guard let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return "正则不合法：\(pattern)"
        }
        var hits: [String] = []
        var scanned = 0
        if let en = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let f as URL in en {
                if f.path.contains("/.") && !f.path.hasPrefix(base.path + "/.") { continue }
                let size = ((try? f.resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0
                if size == 0 || size > 2_000_000 { continue }
                guard let text = try? String(contentsOf: f, encoding: .utf8) else { continue }
                scanned += 1
                let lines = text.components(separatedBy: "\n")
                for (i, line) in lines.enumerated() {
                    let ns = line as NSString
                    if rx.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) != nil {
                        hits.append("\(f.path):\(i + 1): \(String(line.prefix(200)))")
                        if hits.count >= 200 { break }
                    }
                }
                if hits.count >= 200 { break }
            }
        }
        return clip(hits.isEmpty ? "无匹配（扫描 \(scanned) 文件）" : hits.joined(separator: "\n"))
    }

    // MARK: - shell

    static func shell(_ cmd: String) async -> String {
        let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "命令为空" }

        if Prefs.execMode == "remote", !Prefs.runnerURL.isEmpty {
            return await remoteShell(trimmed)
        }
        return localShell(trimmed)
    }

    static func localShell(_ cmd: String) -> String {
#if canImport(Darwin)
        // iOS SDK 把 popen/pclose 标成 __swift_unavailable，只能用 posix_spawn 自己接管道
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { return "pipe 创建失败" }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_adddup2(&actions, fds[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, fds[1], STDERR_FILENO)
        posix_spawn_file_actions_addclose(&actions, fds[0])
        posix_spawn_file_actions_addclose(&actions, fds[1])

        let parts: [String] = ["/bin/sh", "-c", cmd]
        var argv: [UnsafeMutablePointer<CChar>?] = parts.map { strdup($0) }
        argv.append(nil)
        var envp: [UnsafeMutablePointer<CChar>?] = [nil]

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, "/bin/sh", &actions, nil, argv, envp)

        posix_spawn_file_actions_destroy(&actions)
        for p in argv where p != nil { free(p) }
        close(fds[1])

        guard rc == 0 else {
            close(fds[0])
            return "无法创建进程（errno \(rc)）：沙盒限制。\n" +
                   "① 用 TrollStore 版 IPA 安装（带 platform-application 权限）；或\n" +
                   "② 设置里把执行模式改成「远程 runner」，连电脑上的 lcs_agent --web。"
        }

        var out = ""
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fds[0], &buf, buf.count)
            if n <= 0 { break }
            out += String(decoding: buf[0..<n], as: UTF8.self)
            if out.count > maxOutput { break }
        }
        close(fds[0])
        var status: Int32 = 0
        _ = waitpid(pid, &status, 0)
        return out.isEmpty ? "(无输出)" : clip(out)
#else
        return "当前平台不支持本地 shell（只在 iOS 上启用）"
#endif
    }

    static func remoteShell(_ cmd: String) async -> String {
        var s = Prefs.runnerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s + "/api/exec") else {
            return "runner 地址不合法：\(Prefs.runnerURL)"
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !Prefs.runnerToken.isEmpty {
            req.setValue(Prefs.runnerToken, forHTTPHeaderField: "X-Runner-Token")
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["cmd": cmd])
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? ""
            return "[remote HTTP \(code)]\n" + clip(body)
        } catch {
            return "runner 不可达（\(Prefs.runnerURL)）：\(error.localizedDescription)"
        }
    }

    // MARK: - http

    static func httpGet(_ urlString: String) async -> String {
        guard let url = URL(string: urlString) else { return "URL 不合法" }
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        req.setValue("LCS-Agent-iOS/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "(二进制 \(data.count) 字节)"
            return clip("HTTP \(code)\n" + body)
        } catch {
            return "请求失败：\(error.localizedDescription)"
        }
    }
}
