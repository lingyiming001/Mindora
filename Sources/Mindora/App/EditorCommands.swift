import SwiftUI

struct MindoraEditorKey: FocusedValueKey { typealias Value = EditorModel }
extension FocusedValues {
    var mindoraEditor: EditorModel? {
        get { self[MindoraEditorKey.self] }
        set { self[MindoraEditorKey.self] = newValue }
    }
}

struct EditorCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.mindoraEditor) private var model
    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("键盘快捷键") { openWindow(id: "shortcuts") }.keyboardShortcut("/")
        }
        CommandGroup(replacing: .newItem) {
            Button("新建思维导图") {
                model?.finishEditing?(); LibraryStore.shared.newMap()
            }.keyboardShortcut("n")
            Button("新建文件夹…") { LibraryStore.shared.promptNewFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("打开…") { WorkspaceStore.shared.chooseFile() }.keyboardShortcut("o")
        }
        CommandGroup(after: .newItem) {
            Button("返回资料库") { _ = WorkspaceStore.shared.showFolder(WorkspaceStore.shared.fileURL?.deletingLastPathComponent()) }
                .keyboardShortcut("[").disabled(model == nil)
            Menu("打开最近") {
                ForEach(LibraryStore.shared.recentURLs, id: \.self) { url in
                    Button(url.deletingPathExtension().lastPathComponent) { WorkspaceStore.shared.openFile(url) }
                }
            }
        }
        CommandGroup(replacing: .undoRedo) {
            Button("撤销\(model?.undoName ?? "")") {
                if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.undoManager?.undo() }
                else { model?.finishEditing?(); model?.undo() }
            }.keyboardShortcut("z").disabled(model == nil)
            Button("重做\(model?.redoName ?? "")") {
                if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.undoManager?.redo() }
                else { model?.finishEditing?(); model?.redo() }
            }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(model == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button("保存") { save(asCopy: false) }.keyboardShortcut("s").disabled(model == nil)
            Button("另存为…") { save(asCopy: true) }.keyboardShortcut("s", modifiers: [.command, .shift]).disabled(model == nil)
        }
        CommandGroup(after: .importExport) {
            Button("导入 Markdown / OPML / JSON…") {
                guard let model else { return }; model.finishEditing?(); ImportExportService.importFile(into: model)
            }.keyboardShortcut("i", modifiers: [.command, .shift]).disabled(model == nil)
            Menu("导出") {
                ForEach(ExportFormat.allCases) { format in
                    Button(format.label + "…") { guard let model else { return }; model.finishEditing?(); ImportExportService.export(model.document, format: format, model: model) }
                }
            }.disabled(model == nil)
        }
        CommandMenu("AI") {
            Button("打开 AI 助手") { WorkspaceStore.shared.showWorkspaceWindow(); openWindow(id: "ai-assistant") }.keyboardShortcut("a", modifiers: [.command, .shift])
            Button("停止 AI 请求") { AIAssistantStore.shared.stop() }
        }
        CommandMenu("插入") {
            Button("网址链接…") { model?.insertContent(.link) }.keyboardShortcut("k", modifiers: [.command, .option]).disabled(model?.selectedID == nil)
            Button("代码块…") { model?.insertContent(.code) }.keyboardShortcut("c", modifiers: [.command, .option]).disabled(model?.selectedID == nil)
        }
        CommandMenu("主题") {
            Button("添加子主题") { model?.finishEditing?(); model?.addChild() }.keyboardShortcut("k", modifiers: .command).disabled(model == nil)
            Button("添加同级主题") { model?.finishEditing?(); model?.addSibling() }.keyboardShortcut("k", modifiers: [.command, .shift]).disabled(model == nil)
            Button("编辑文字") { model?.request(.editSelection) }.keyboardShortcut("e").disabled(model == nil)
            Divider()
            Button("创建主题副本") { model?.duplicateSelection() }.keyboardShortcut("d").disabled(model == nil)
            Button("展开 / 折叠") { model?.toggleCollapse() }.keyboardShortcut(".").disabled(model == nil)
            Button("上移") { model?.reorderSelected(by: -1) }.keyboardShortcut(.upArrow, modifiers: [.command, .option]).disabled(model == nil)
            Button("下移") { model?.reorderSelected(by: 1) }.keyboardShortcut(.downArrow, modifiers: [.command, .option]).disabled(model == nil)
            Divider()
            Button("从模板开始…") { model?.showsTemplates = true }.disabled(model == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("搜索主题…") { model?.finishEditing?(); model?.showsOutline = true; model?.sidebarSection = .outline; model?.isSearchPresented = true }.keyboardShortcut("f").disabled(model == nil)
            Button("命令面板…") { model?.finishEditing?(); model?.showsCommandPalette = true }.keyboardShortcut("p", modifiers: [.command, .shift]).disabled(model == nil)
        }
        CommandGroup(after: .toolbar) {
            Button("适应画布") { model?.finishEditing?(); model?.request(.fit) }.keyboardShortcut("0").disabled(model == nil)
            Button("定位选中主题") { model?.request(.centerSelection) }.keyboardShortcut("l").disabled(model == nil)
            Button("显示 / 隐藏侧边栏") { model?.showsOutline.toggle() }.keyboardShortcut("1", modifiers: [.command, .option]).disabled(model == nil)
            Button("显示 / 隐藏属性") { model?.showsInspector.toggle() }.keyboardShortcut("2", modifiers: [.command, .option]).disabled(model == nil)
            Button("专注模式") {
                model?.toggleFocusMode()
            }.keyboardShortcut("f", modifiers: [.command, .shift]).disabled(model == nil)
        }
    }
    private func save(asCopy: Bool) {
        WorkspaceStore.shared.save(asCopy: asCopy)
    }
}
