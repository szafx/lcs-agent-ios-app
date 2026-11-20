# 小酱 Code for iOS

> 状态：**WIP — 待 CI 首跑**。本机是 Windows，没有 Swift/macOS 工具链，`LCSAgent/*.swift` 只做了结构自检（括号配对、plist/YAML 解析通过），真正编译验证在 GitHub Actions 第一次运行时完成。Python 侧的 `/api/exec` 远程执行端点已本机实测通过。

把手机版编码智能体做成真正的 App：SwiftUI 界面 + 工具调用循环 + GitHub Actions 出包。
**不用 Mac**——工程由 `project.yml` 生成，编译在 GitHub 的 macOS runner 上跑。

```
LCSAgent/           Swift 源码（7 个文件，约 900 行）
project.yml         XcodeGen 工程描述（改工程只改这个）
entitlements.plist  TrollStore 版注入的权限
.github/workflows/build-ipa.yml   出包流水线
```

---

## 0. 已经内置的默认配置（装上就能用）

| 项 | 值 |
|---|---|
| Base URL | `https://api.xingchiapi.com/v1` |
| API Key | `sk-d307…293b`（写在 `Models.swift` 的 `Builtin.key`） |
| 模型 | `gpt-6.1-sol`（实测该 Key 只可见这一个模型） |
| 协议 | **`/v1/responses`（Responses API）** —— 该网关已停用 `/v1/chat/completions` |
| 客户端指纹 | `User-Agent: codex_cli_rs/0.20.0 …` + `originator: codex_cli_rs` —— 网关只放行编程客户端，脚本/第三方聊天客户端会被 403 |

设置页有一键「恢复内置默认」。改 Key/模型不影响其它设置。

---

## 1. 出包（Windows 上就能做）

仓库已建好：**https://github.com/szafx/lcs-agent-ios-app**（public，macOS runner 免费）

Key 不在仓库里：构建时由 GitHub Secret `XC_API_KEY` 注入生成 `LCSAgent/BuiltinKey.swift`，
所以流水线出的 IPA 内置 Key，仓库本身干净（公开也不泄露）。

**一条命令：建仓库/推送/触发/等结果/拉 IPA**

```powershell
gh auth status          # 未登录先 gh auth login
powershell -ExecutionPolicy Bypass -File scripts\ci-build.ps1
```

脚本会：检查登录 → 提交 → 建/复用仓库 → `gh workflow run` → `gh run watch` → 失败自动打 `--log-failed` → 成功把 IPA 拉到 `dist/`。

| 产物 | 用途 |
|---|---|
| `LCSAgent-unsigned.ipa` | Sideloadly / PlumeImpactor / 企业签名 |
| `LCSAgent-trollstore.ipa` | **TrollStore 专用**，已用 ldid 注入 `platform-application`，装完 App 内可直接执行 shell、读写 `/var/mobile` |

> 公开仓库跑 macOS runner 不扣额度；私有仓库按 macOS 10 倍计费（2000 分钟/月）。

---

## 2. 安装

**TrollStore（推荐，越狱机或已装 TrollStore）**

1. 下载 artifact → 解压 → `LCSAgent-trollstore.ipa`
2. TrollStore → 右上角 + → 选这个 ipa → Install
3. 打开「小酱Code」→ 右上角齿轮 → 填 API Key → 完成

**普通签名（不越狱）**

1. `LCSAgent-unsigned.ipa` → Sideloadly / PlumeImpactor 用 Apple ID 签装
2. 设置 → 通用 → VPN与设备管理 → 信任
3. 因为是 iOS 16，还要开：设置 → 隐私与安全性 → **开发者模式** → 重启

> 不越狱时 App 没有 exec 权限，**执行方式选「远程 runner」**：电脑上跑
> `python3 lcs_agent.py --web 8765`，App 里填 `http://<电脑IP>:8765`。
> 同一个 Wi-Fi 下直接可用；出门就配 frp/Tailscale 打洞（照搬 `手机远程控制` 那套）。

---

## 3. 用起来

- 输入框直接下指令：「把 Documents 里的 a.py 改成带重试的版本」
- 每个工具调用是一张绿色小卡片，显示命令与真实回显
- 右上角齿轮：Base URL / API Key / 模型名 / 执行方式 / 允许系统路径 / 最大步数
- 「测试连接」打的是网关 `/health`，先确认网络通

默认配置已经是星驰网关 `https://api.xingchiapi.com/v1` + 内置 Key + `gpt-6.1-sol`，**装完直接能用**，不用填任何东西。

---

## 3.1 网关的三个坑（已在本项目里处理掉）

| 坑 | 表现 | 处理 |
|---|---|---|
| 只开 Responses API | `chat/completions` 直接 400 `chat_completions_disabled` | 全部走 `/v1/responses`，工具用扁平 schema，结果用 `function_call_output` 回灌 |
| 客户端 allowlist | 403 `client_not_allowed`，提示只支持 Codex/Claude Code/Cursor… | 请求头带 `User-Agent: codex_cli_rs/...` + `originator: codex_cli_rs`（实测 6 种 UA 全部放行） |
| 模型目录极小 | `/v1/models` 只有一条 | 默认 `gpt-6.1-sol`，换 Key 后重新拉一遍 |

证据：`evidence/responses_probe.json`（两轮工具往返原文）、`evidence/live_run_responses.txt`（真实任务：ls→read→edit→shell→done，输出 2）

---

## 4. App 里的工具

| 工具 | 说明 | 需要权限 |
|---|---|---|
| `read` `write` `edit` `ls` `glob` `grep` | 文件读写，默认限制在 App Documents | 无 |
| 同上 + 绝对路径 | 读写 `/var/mobile` 等 | TrollStore 版 + 设置里开「允许系统绝对路径」 |
| `shell` | `popen` 执行命令 | TrollStore 版；否则自动走远程 runner |
| `http_get` | 发请求 | 无 |
| `done` | 收工汇报 | 无 |

执行方式两档：

- **本机**：`popen(cmd)` 直接跑（沙盒里会失败，App 会把失败原因回给模型，模型自动改用文件工具）
- **远程 runner**：POST `{runner}/api/exec`，由电脑上的 `lcs_agent.py --web` 执行，返回 stdout

---

## 5. 改代码的流程

```
改 project.yml（加文件/改设置） → git push → Actions 自动出包 → TrollStore 覆盖安装
```

新增 Swift 文件直接丢进 `LCSAgent/` 目录即可，XcodeGen 每次构建都会重新扫描。
改了 `project.yml` 里的 bundle id 记得同步改 `INFOPLIST_FILE` 之外的东西（一般不用动）。

---

## 6. 已知边界

- 没越狱/TrollStore 时，`shell` 必然失败——这是 iOS 沙盒决定的，不是 bug
- 后台切走会被挂起，长任务建议用远程 runner 模式（命令跑在电脑上，App 只等结果）
- 没有 App 图标（未带 Assets.xcassets），要图标就加一个 `Assets.xcassets/AppIcon.appiconset` 并在 project.yml 里加进 sources
- 首次构建如果 `brew install ldid` 失败，TrollStore 版会退化成无权限版（workflow 里有 warning，不中断）

---

## 7. 与电脑版的差异

| | 电脑版 `lcs_agent.py` | 这个 App |
|---|---|---|
| 工具 | 9 个，含 `python` | 9 个，去掉 `python`（iOS 无解释器），shell 需权限 |
| 运行位置 | 任意终端 | 手机原生 App |
| 交互 | 终端 / 浏览器 | 原生 SwiftUI |
| 常驻 | 进程级 | iOS 后台限制 |

两边共用同一套模型接口与同一份人格设定（`SystemPrompt.text` 对应 `system_prompt.md`）。
