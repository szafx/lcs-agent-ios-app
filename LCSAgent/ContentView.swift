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
            .task { engine.reset() }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
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
