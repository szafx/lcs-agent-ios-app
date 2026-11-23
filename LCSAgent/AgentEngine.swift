import Foundation
import Combine

/// 走 OpenAI Responses API（/v1/responses）的智能体循环。
/// 与网关行为一致：工具以扁平 schema 提交，返回 output 数组，
/// 工具结果用 {"type":"function_call_output","call_id":...} 回灌。
@MainActor
final class AgentEngine: ObservableObject {
    @Published var items: [ChatItem] = []
    @Published var busy: Bool = false
    @Published var stats = UsageStats()

    /// Responses API 的上下文条目（message / function_call / function_call_output）
    private var input: [[String: Any]] = []

    nonisolated init() {}

    func reset() {
        input = []
        stats.contextTokens = 0
        stats.outputTokens = 0
        items = [ChatItem(role: .assistant,
                          text: "小酱 Code 就绪\n模型：\(Prefs.model)\n网关：\(Prefs.baseURL)")]
    }

    /// 拉一次余额 / 今日用量
    func refreshStats() async {
        guard let d = await API.usage() else { return }
        var s = stats
        s.balance = num(d["remaining"]) ?? num(d["balance"]) ?? s.balance
        if let u = d["usage"] as? [String: Any], let today = u["today"] as? [String: Any] {
            s.todayRequests = Int(num(today["requests"]) ?? 0)
            s.todayCost = num(today["actual_cost"]) ?? 0
        }
        s.updatedAt = Date()
        stats = s
    }

    func send(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !busy else { return }
        items.append(ChatItem(role: .user, text: t))
        let userItem: [String: Any] = [
            "type": "message",
            "role": "user",
            "content": [["type": "input_text", "text": t] as [String: Any]]
        ]
        input.append(userItem)
        busy = true
        Task { await runLoop() }
    }

    private func runLoop() async {
        var step = 0
        while step < Prefs.maxSteps {
            step += 1
            do {
                let resp = try await API.responses(items: input, tools: ToolBox.schema)
                let output = (resp["output"] as? [[String: Any]]) ?? []
                let text = API.outputText(resp)
                let calls = output.filter { ($0["type"] as? String) == "function_call" }

                if let u = resp["usage"] as? [String: Any] {
                    let inTok = Int(num(u["input_tokens"]) ?? 0)
                    let outTok = Int(num(u["output_tokens"]) ?? 0)
                    if inTok > 0 { stats.contextTokens = inTok }
                    if outTok > 0 { stats.outputTokens = outTok }
                }

                if !text.isEmpty {
                    items.append(ChatItem(role: .assistant, text: text))
                }

                // 只回灌 message 与 function_call，reasoning 之类的条目丢掉
                for item in output {
                    let t = (item["type"] as? String) ?? ""
                    if t == "message" || t == "function_call" {
                        input.append(item)
                    }
                }

                if calls.isEmpty { break }

                var finished = false
                for call in calls {
                    let name = (call["name"] as? String) ?? ""
                    let argStr = (call["arguments"] as? String) ?? "{}"
                    let callID = (call["call_id"] as? String) ?? UUID().uuidString

                    items.append(ChatItem(role: .tool,
                                          text: "⚙ \(name) \(String(argStr.prefix(160)))",
                                          tool: name))

                    var args: [String: Any] = [:]
                    if let d = argStr.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: d),
                       let dict = obj as? [String: Any] {
                        args = dict
                    }

                    let out = await ToolBox.run(name: name, args: args)
                    items.append(ChatItem(role: .tool,
                                          text: String(out.prefix(1500)),
                                          tool: "  ↳"))

                    let resultItem: [String: Any] = [
                        "type": "function_call_output",
                        "call_id": callID,
                        "output": out
                    ]
                    input.append(resultItem)

                    if name == "done" {
                        let summary = (args["summary"] as? String) ?? "完成"
                        items.append(ChatItem(role: .assistant, text: "✅ " + summary))
                        finished = true
                        break
                    }
                }
                if finished { break }
            } catch {
                items.append(ChatItem(role: .error, text: error.localizedDescription))
                break
            }
        }
        busy = false
        await refreshStats()
    }
}
