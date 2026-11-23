import SwiftUI

struct ContentView: View {
    @StateObject private var engine = AgentEngine()
    @State private var input: String = ""
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(engine.items) { item in
                            Bubble(item: item).id(item.id)
                        }
                    }
                    .padding(12)
                }
                .background(Color(.systemGroupedBackground))
                .onChange(of: engine.items.count) { _ in
                    if let last = engine.items.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .navigationTitle("小酱 Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("新会话") { engine.reset() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .task {
                engine.reset()
                await engine.refreshStats()
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            statusBar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    quick("看看 Documents 里有什么")
                    quick("把这个目录的报错修掉")
                    quick("写个脚本批量改文件名")
                    quick("把这段代码优化一下")
                }
                .padding(.horizontal, 12)
            }
            HStack(spacing: 8) {
                TextField("让它干活…", text: $input, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    let t = input
                    input = ""
                    engine.send(t)
                } label: {
                    Image(systemName: engine.busy ? "hourglass" : "paperplane.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(engine.busy ? Color.gray : Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(Circle())
                }
                .disabled(engine.busy)
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func quick(_ text: String) -> some View {
        Button {
            input = text
        } label: {
            Text(text)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(.secondarySystemBackground))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 状态栏（模型 / 上下文 / 余额）

    private var statusBar: some View {
        HStack(spacing: 10) {
            Text(Prefs.model)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text(ctxText)
                .monospacedDigit()
            Text("·").opacity(0.35)
            Text(moneyText)
                .monospacedDigit()
            if engine.busy {
                ProgressView().scaleEffect(0.6)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
    }

    private var effectiveLimit: Int? {
        if Prefs.autoContext, let auto = ModelCatalog.contextLimit(for: Prefs.model) {
            return auto
        }
        return Prefs.contextLimit > 0 ? Prefs.contextLimit : nil
    }

    private var ctxText: String {
        let used = engine.stats.contextTokens
        guard let limit = effectiveLimit else {
            return used > 0 ? "ctx \(kfmt(used))" : "ctx —"
        }
        if used <= 0 { return "ctx —/\(kfmt(limit))" }
        return "ctx \(kfmt(used))/\(kfmt(limit))"
    }

    private var moneyText: String {
        if let b = engine.stats.balance { return String(format: "$%.2f", b) }
        return "$—"
    }

    private func kfmt(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }
}

struct Bubble: View {
    let item: ChatItem

    var body: some View {
        HStack {
            if item.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 3) {
                if let tag = item.tool, item.role == .tool {
                    Text(tag)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.green)
                }
                Text(item.text)
                    .font(item.role == .tool ? .system(size: 12, design: .monospaced) : .body)
                    .textSelection(.enabled)
            }
            .padding(10)
            .background(background)
            .foregroundColor(foreground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            if item.role != .user { Spacer(minLength: 24) }
        }
    }

    private var background: Color {
        switch item.role {
        case .user: return .accentColor
        case .assistant: return Color(.secondarySystemBackground)
        case .tool: return Color(.tertiarySystemBackground)
        case .error: return Color.red.opacity(0.12)
        }
    }

    private var foreground: Color {
        switch item.role {
        case .user: return .white
        case .error: return .red
        default: return .primary
        }
    }
}
