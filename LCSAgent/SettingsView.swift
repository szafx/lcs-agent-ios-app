import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("base_url") private var baseURL = Builtin.base
    @AppStorage("api_key") private var apiKey = Builtin.key
    @AppStorage("model") private var model = Builtin.model
    @AppStorage("exec_mode") private var execMode = "local"
    @AppStorage("runner_url") private var runnerURL = ""
    @AppStorage("runner_token") private var runnerToken = ""
    @AppStorage("allow_system_paths") private var allowSystem = false
    @AppStorage("max_steps") private var maxSteps = 30
    @AppStorage("context_limit") private var contextLimit = 200_000

    @State private var testResult = ""
    @State private var testing = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("模型服务")) {
                    TextField("Base URL", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("API Key (sk-...)", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("模型名", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(testing ? "测试中…" : "测试连接") {
                        testing = true
                        Task {
                            testResult = await API.ping()
                            testing = false
                        }
                    }
                    .disabled(testing)
                    if !testResult.isEmpty {
                        Text(testResult)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Button("恢复内置默认") {
                        baseURL = Builtin.base
                        apiKey = Builtin.key
                        model = Builtin.model
                        testResult = "已恢复：\(Builtin.model)"
                    }
                    .foregroundColor(.orange)
                }

                Section(header: Text("执行方式"),
                        footer: Text("本机：App 自己跑命令，需要 TrollStore 版 IPA（带 platform-application 权限）。远程：把命令发给电脑上的 lcs_agent.py --web，由电脑执行。")) {
                    Picker("模式", selection: $execMode) {
                        Text("本机").tag("local")
                        Text("远程 runner").tag("remote")
                    }
                    .pickerStyle(.segmented)

                    if execMode == "remote" {
                        TextField("runner 地址，如 http://192.168.1.5:8765", text: $runnerURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        SecureField("runner token（可选）", text: $runnerToken)
                    }
                }

                Section(header: Text("文件权限"),
                        footer: Text("开启后 agent 可以读写 /var/mobile 等系统路径（仅越狱/TrollStore 环境有效）。")) {
                    Toggle("允许系统绝对路径", isOn: $allowSystem)
                }

                Section(header: Text("运行参数")) {
                    Stepper("最大步数：\(maxSteps)", value: $maxSteps, in: 5...80)
                    HStack {
                        Text("上下文上限")
                        Spacer()
                        TextField("200000", value: $contextLimit, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                    }
                }

                Section(header: Text("关于")) {
                    HStack { Text("版本"); Spacer(); Text("1.0.0").foregroundColor(.secondary) }
                    HStack { Text("工作目录"); Spacer()
                        Text("Documents").foregroundColor(.secondary) }
                    Link("星驰网关", destination: URL(string: "https://api.xingchiapi.com")!)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
