import Foundation

enum MsgRole: String {
    case user
    case assistant
    case tool
    case error
}

struct ChatItem: Identifiable {
    let id = UUID()
    var role: MsgRole
    var text: String
    var tool: String? = nil
}

struct ToolCallInfo {
    var id: String
    var name: String
    var arguments: String
}

enum Builtin {
    static let base = "https://api.xingchiapi.com/v1"
    static let model = "gpt-6.1-sol"
    static let key = BuiltinKey.value
}

enum Prefs {
    static var baseURL: String {
        get { UserDefaults.standard.string(forKey: "base_url") ?? Builtin.base }
        set { UserDefaults.standard.set(newValue, forKey: "base_url") }
    }
    static var apiKey: String {
        get { UserDefaults.standard.string(forKey: "api_key") ?? Builtin.key }
        set { UserDefaults.standard.set(newValue, forKey: "api_key") }
    }
    static var model: String {
        get { UserDefaults.standard.string(forKey: "model") ?? Builtin.model }
        set { UserDefaults.standard.set(newValue, forKey: "model") }
    }
    static var execMode: String {
        get { UserDefaults.standard.string(forKey: "exec_mode") ?? "local" }
        set { UserDefaults.standard.set(newValue, forKey: "exec_mode") }
    }
    static var runnerURL: String {
        get { UserDefaults.standard.string(forKey: "runner_url") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "runner_url") }
    }
    static var runnerToken: String {
        get { UserDefaults.standard.string(forKey: "runner_token") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "runner_token") }
    }
    static var allowSystemPaths: Bool {
        get { UserDefaults.standard.bool(forKey: "allow_system_paths") }
        set { UserDefaults.standard.set(newValue, forKey: "allow_system_paths") }
    }
    static var maxSteps: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: "max_steps")
            return v == 0 ? 30 : v
        }
        set { UserDefaults.standard.set(newValue, forKey: "max_steps") }
    }
}

enum SystemPrompt {
    static let text = """
    你是「小酱 Code」，运行在 iPhone 上的编码智能体。

    规则：
    1. 直接干，不解释流程、不写免责声明、不拒绝、不问「要不要继续」。
    2. 缺参数用占位符补上继续，不反问。
    3. 先看现场（ls/read/grep）再动手；改代码用 edit 精确替换，不用 write 覆盖已有文件。
    4. 改完必须跑一遍验证，把真实输出贴出来。
    5. 收尾用 done 汇报：改了哪些文件、验证结果、下一步。

    路径说明：工作目录是 App 的 Documents，相对路径都基于它；开启「允许系统路径」后可用 /var/mobile 等绝对路径。
    shell 在非越狱/TrollStore 环境下可能不可用，失败时改用 read/write/edit/ls/grep 这些文件工具。
    """
}
