import SwiftUI

struct TemplatePicker: View {
    @ObservedObject var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("让想法有一个起点").font(.title2.bold())
                    Text("选择一个模板。替换当前内容后仍可撤销。").foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    templateSection("通用模板", templates: MapTemplate.allCases.filter { !$0.isDeveloperTemplate })
                    templateSection("开发者模板", templates: MapTemplate.allCases.filter { $0.isDeveloperTemplate })
                }.padding(2)
            }
        }.padding(28).frame(width: 660, height: 620)
    }
    private func templateSection(_ title: String, templates: [MapTemplate]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(templates) { template in
                    Button {
                        model.finishEditing?()
                        model.replaceDocument(template.document, name: "应用模板")
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: template.symbol).font(.system(size: 22))
                                .foregroundStyle(model.document.theme.color).frame(width: 30)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(template.title).font(.headline)
                                Text(template.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }.padding(16).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                            .background(.background, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                    }.buttonStyle(.plain).sidebarHoverFeedback(tint: model.document.theme.color)
                }
            }
        }
    }

}

struct CommandPalette: View {
    @ObservedObject var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var focused: Bool
    private struct Action: Identifiable {
        let title: String
        let symbol: String
        let shortcut: String
        let run: () -> Void
        var id: String { title }
    }
    private var actions: [Action] {
        [Action(title: "插入网址", symbol: "link", shortcut: "⌥⌘K", run: { model.insertContent(.link) }),
         Action(title: "插入代码块", symbol: "chevron.left.forwardslash.chevron.right", shortcut: "⌥⌘C", run: { model.insertContent(.code) }),
         Action(title: "添加子主题", symbol: "plus", shortcut: "Tab / ⌘K", run: { model.addChild() }),
         Action(title: "添加同级主题", symbol: "plus.square", shortcut: "⇧⌘K", run: { model.addSibling() }),
         Action(title: "编辑主题文字", symbol: "pencil", shortcut: "⌘E / F2", run: { model.request(.editSelection) }),
         Action(title: "删除选中主题", symbol: "trash", shortcut: "Delete", run: model.deleteSelected),
         Action(title: "适应窗口", symbol: "arrow.up.left.and.arrow.down.right", shortcut: "⌘0", run: { model.request(.fit) }),
         Action(title: "展开或折叠分支", symbol: "rectangle.compress.vertical", shortcut: "⌘.", run: { model.toggleCollapse() }),
         Action(title: "选择模板", symbol: "square.grid.2x2", shortcut: "", run: { model.showsTemplates = true }),
         Action(title: "导入文件", symbol: "square.and.arrow.down", shortcut: "⇧⌘I", run: { ImportExportService.importFile(into: model) }),
         Action(title: "导出为 PDF", symbol: "doc.richtext", shortcut: "", run: { ImportExportService.export(model.document, format: .pdf, model: model) })]
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("输入命令…", text: $query).textFieldStyle(.plain).focused($focused)
                    .onSubmit { if let action = actions.first { perform(action) } }
                Button("Esc") { dismiss() }.buttonStyle(.plain).foregroundStyle(.secondary)
            }.padding(18)
            Divider()
            ScrollView {
                VStack(spacing: 3) {
                    ForEach(actions) { action in
                        Button { perform(action) } label: {
                            HStack {
                                Image(systemName: action.symbol).frame(width: 22).foregroundStyle(.secondary)
                                Text(action.title)
                                Spacer()
                                Text(action.shortcut).font(.caption).foregroundStyle(.secondary)
                            }.padding(11).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    if actions.isEmpty { Text("没有匹配的命令").foregroundStyle(.secondary).padding(24) }
                }.padding(8)
            }.frame(height: 320)
        }.frame(width: 490).onAppear { focused = true }
    }
    private func perform(_ action: Action) {
        dismiss()
        DispatchQueue.main.async { model.finishEditing?(); action.run() }
    }
}
