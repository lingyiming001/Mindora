import SwiftUI

struct WorkspaceIcon: View {
    let workspace: LibraryWorkspace?
    var size: CGFloat = 32
    var body: some View {
        let color = Color(nsColor: NSColor(hex: workspace?.iconColorHex ?? "6264D9") ?? .systemIndigo)
        Group {
            if let text = workspace?.iconText, !text.isEmpty { Text(text).font(.system(size: size * 0.5, weight: .semibold)) }
            else { Image(systemName: workspace?.iconSymbol ?? "square.stack.3d.up.fill").font(.system(size: size * 0.46)) }
        }.foregroundStyle(color).frame(width: size, height: size)
            .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: size * 0.28))
            .accessibilityHidden(true)
    }
}

struct WorkspaceDetailsEditor: View {
    let workspace: LibraryWorkspace?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var introduction: String
    @State private var symbol: String
    @State private var iconText: String
    @State private var colorHex: String
    @State private var errorText = ""
    @FocusState private var nameFocused: Bool
    private let symbols = ["square.stack.3d.up.fill", "briefcase.fill", "book.fill", "laptopcomputer", "chevron.left.forwardslash.chevron.right", "lightbulb.fill", "graduationcap.fill", "heart.fill", "person.2.fill", "star.fill", "house.fill", "folder.fill"]
    private let colors = ["6264D9", "2C8A78", "4D91B8", "C86B48", "AD6981", "657186"]
    init(workspace: LibraryWorkspace?) {
        self.workspace = workspace
        _name = State(initialValue: workspace?.name ?? "")
        _introduction = State(initialValue: workspace?.introduction ?? "")
        _symbol = State(initialValue: workspace?.iconSymbol ?? "square.stack.3d.up.fill")
        _iconText = State(initialValue: workspace?.iconText ?? "")
        _colorHex = State(initialValue: workspace?.iconColorHex ?? "6264D9")
    }
    private var preview: LibraryWorkspace {
        LibraryWorkspace(id: workspace?.id ?? UUID(), name: name, path: workspace?.path ?? "", bookmark: nil, iconSymbol: symbol, iconText: iconText, introduction: introduction, iconColorHex: colorHex)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                WorkspaceIcon(workspace: preview, size: 56)
                VStack(alignment: .leading, spacing: 5) {
                    Text(workspace == nil ? "新建工作空间" : "编辑工作空间").font(.title2.bold())
                    Text("用图标和介绍，为这个空间赋予自己的风格。").font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("名称").font(.headline)
                TextField("例如：产品研发、学习笔记", text: $name).textFieldStyle(.roundedBorder).focused($nameFocused)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text("图标").font(.headline); Spacer(); Text("选择预设，或输入 Emoji / 缩写").font(.caption).foregroundStyle(.secondary) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                    ForEach(symbols, id: \.self) { option in
                        Button { symbol = option; iconText = "" } label: {
                            Image(systemName: option).font(.system(size: 18)).frame(maxWidth: .infinity).frame(height: 40)
                                .foregroundStyle(Color(nsColor: NSColor(hex: colorHex) ?? .systemIndigo))
                                .background(iconText.isEmpty && symbol == option ? InterfaceStyle.accent.opacity(0.12) : InterfaceStyle.panel, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(iconText.isEmpty && symbol == option ? InterfaceStyle.accent : .clear))
                        }.buttonStyle(.plain).accessibilityLabel(option)
                    }
                }
                HStack {
                    TextField("Emoji 或缩写（最多 2 字）", text: $iconText).textFieldStyle(.roundedBorder)
                    ForEach(colors, id: \.self) { hex in
                        Button { colorHex = hex } label: {
                            Circle().fill(Color(nsColor: NSColor(hex: hex)!)).frame(width: 20, height: 20)
                                .overlay { if hex == colorHex { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white) } }
                        }.buttonStyle(.plain).accessibilityLabel("图标颜色 \(hex)")
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("介绍").font(.headline); Spacer(); Text("\(introduction.count)/500").font(.caption).foregroundStyle(introduction.count > 500 ? Color.red : Color.secondary) }
                TextField("这个空间用来做什么？", text: $introduction, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(3...5)
            }
            if !errorText.isEmpty { Text(errorText).font(.caption).foregroundStyle(.red) }
            HStack {
                Text("信息保存在本机，修改不影响空间内的文件。").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(workspace == nil ? "创建空间" : "保存") { save() }.buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 60 || introduction.count > 500 || iconText.count > 2)
            }
        }.padding(24).frame(width: 520).tint(InterfaceStyle.accent)
            .onAppear { nameFocused = true }
    }
    private func save() {
        let catalog = WorkspaceCatalog.shared
        let success: Bool
        if let workspace {
            success = catalog.updateDetails(workspace.id, name: name, symbol: symbol, iconText: iconText, introduction: introduction, colorHex: colorHex)
        } else {
            success = catalog.create(name: name.trimmingCharacters(in: .whitespacesAndNewlines), iconSymbol: symbol, iconText: iconText, introduction: introduction, colorHex: colorHex)
        }
        if success { dismiss() }
        else { errorText = LibraryStore.shared.errorMessage ?? "保存失败，请重试。" }
    }
}
