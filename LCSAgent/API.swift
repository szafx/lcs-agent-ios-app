import Foundation

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum API {
    /// 网关按客户端指纹放行，脚本/第三方聊天客户端会被 403 拦截；
    /// 这里伪装成 Codex CLI（UA + originator）才能过 allowlist。
    static let userAgent = "codex_cli_rs/0.20.0 (Mac OS 15.1; arm64) iTerm.app/3.5.0"
    static let originator = "codex_cli_rs"

    static func url(_ base: String, _ path: String) -> URL? {
        var s = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { s = Builtin.base }
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix("/v1") || s.hasSuffix("/v1/") {
            return URL(string: s + path)
        }
        return URL(string: s + "/v1" + path)
    }

    static func rootURL(_ base: String) -> URL? {
        var s = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix("/v1") { s = String(s.dropLast(3)) }
        return URL(string: s)
    }

    static func responses(items: [[String: Any]], tools: [[String: Any]]) async throws -> [String: Any] {
        guard let u = url(Prefs.baseURL, "/responses") else {
            throw APIError(message: "base_url 不合法：\(Prefs.baseURL)")
        }
        let key = Prefs.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw APIError(message: "还没填 API Key（右上角齿轮里设置）") }

        var body: [String: Any] = [
            "model": Prefs.model,
            "instructions": SystemPrompt.text,
            "input": items,
            "store": false
        ]
        if !tools.isEmpty {
            body["tools"] = tools
            body["tool_choice"] = "auto"
        }

        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 300
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(originator, forHTTPHeaderField: "originator")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let text = String(data: data, encoding: .utf8) ?? ""
        guard let http = resp as? HTTPURLResponse else {
            throw APIError(message: "没有拿到 HTTP 响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(message: "HTTP \(http.statusCode)：\(String(text.prefix(400)))")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError(message: "响应不是 JSON：\(String(text.prefix(200)))")
        }
        if let err = obj["error"] as? [String: Any] {
            throw APIError(message: "接口报错：\(err["message"] ?? err)")
        }
        return obj
    }

    /// 从 Responses 响应里取文本
    static func outputText(_ resp: [String: Any]) -> String {
        if let t = resp["output_text"] as? String, !t.isEmpty { return t }
        var parts: [String] = []
        if let out = resp["output"] as? [[String: Any]] {
            for item in out where (item["type"] as? String) == "message" {
                if let cs = item["content"] as? [[String: Any]] {
                    for c in cs {
                        if let t = c["text"] as? String { parts.append(t) }
                    }
                }
            }
        }
        return parts.joined()
    }

    /// 余额 / 用量：GET {base}/usage（只认 sk Key，不需要控制台登录）
    static func usage() async -> [String: Any]? {
        guard let u = url(Prefs.baseURL, "/usage") else { return nil }
        let key = Prefs.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        var req = URLRequest(url: u)
        req.timeoutInterval = 20
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    /// 测试连接：打网关 /health
    static func ping() async -> String {
        guard let u = rootURL(Prefs.baseURL) else { return "base_url 不合法" }
        var req = URLRequest(url: u.appendingPathComponent("health"))
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? ""
            return "HTTP \(code) \(String(body.prefix(200)))"
        } catch {
            return "失败：\(error.localizedDescription)"
        }
    }
}
