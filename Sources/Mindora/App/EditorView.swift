import SwiftUI

struct EditorView: View {
    let fileURL: URL?
    @ObservedObject var model: EditorModel
    @ObservedObject private var workspace = WorkspaceStore.shared
    @FocusState private var searchFocused: Bool

    init(model: EditorModel, fileURL: URL?) {
        self.fileURL = fileURL
        _model = ObservedObject(wrappedValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let dockInspector = geometry.size.width >= 1080
                HStack(spacing: 0) {
                    if model.showsOutline {
                        EditorSidebar(model: model) { outline }
                            .frame(width: InterfaceStyle.sidebarWidth)
                            .clipped()
                            .zIndex(1)
                        Rectangle().fill(InterfaceStyle.divider).frame(width: 1)
                    }
                    VStack(spacing: 0) {
                        if model.isSearchPresented { searchBar }
                        MindMapCanvas(model: model)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    }.frame(minWidth: 320)
                        .clipped()
                    if model.showsInspector && dockInspector {
                        Rectangle().fill(InterfaceStyle.divider).frame(width: 1)
                        NodeInspector(model: model).frame(width: InterfaceStyle.inspectorWidth)
                    }
                }
                .overlay(alignment: .trailing) {
                    if model.showsInspector && !dockInspector {
                        NodeInspector(model: model)
                            .frame(width: InterfaceStyle.inspectorWidth)
                            .background(InterfaceStyle.panel)
                            .overlay(alignment: .leading) { Rectangle().fill(InterfaceStyle.divider).frame(width: 1) }
                            .shadow(color: .black.opacity(0.07), radius: 14, x: -5)
                    }
                }
            }
            Divider()
            statusBar
        }
        .frame(minWidth: 820, minHeight: 540)
        .toolbarRole(.editor)
        .tint(model.document.theme.color)
        .toolbar { toolbar }
        .focusedSceneValue(\.mindoraEditor, model)
        .onAppear { applyAppearance() }
        .onChange(of: model.isSearchPresented) { _, shown in if shown { model.sidebarSection = .outline; searchFocused = true } }
        .sheet(item: $model.contentInsertion) { request in NodeContentEditor(model: model, request: request) }
        .sheet(isPresented: $model.showsTemplates) { TemplatePicker(model: model) }
        .sheet(isPresented: $model.showsCommandPalette) { CommandPalette(model: model) }
        .alert("操作未完成", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("好", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
    private func applyAppearance() {
        let value = UserDefaults.standard.string(forKey: "appearance") ?? "system"
        NSApp.appearance = value == "system" ? nil : NSAppearance(named: value == "dark" ? .darkAqua : .aqua)
    }
    private var outline: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.isSearchPresented && !model.searchText.isEmpty {
                HStack {
                    Text("搜索结果"); Spacer(); Text("\(model.searchMatches.count) 项")
                }.font(.system(size: 10)).foregroundStyle(.secondary).padding(14)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if model.isSearchPresented && !model.searchText.isEmpty {
                        if model.searchMatches.isEmpty { Text("没有找到相关主题").foregroundStyle(.secondary).padding(12) }
                        ForEach(model.searchMatches) { node in
                            Button { model.reveal(node.id); model.request(.focus) } label: {
                                Label(node.title.isEmpty ? "无标题" : node.title, systemImage: "magnifyingglass")
                                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading).padding(8)
                            }.buttonStyle(.plain).sidebarHoverFeedback(tint: model.document.theme.color)
                        }
                    } else { OutlineNodeRow(node: model.document.root, model: model, depth: 0) }
                }.padding(8)
            }
            Divider()
            HStack { Text("Tab 子主题"); Spacer(); Text("⇧⌘K 同级") }
                .font(.system(size: 10)).foregroundStyle(.tertiary).padding(12)
        }.background(InterfaceStyle.panel)
    }
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索主题、备注和标签", text: $model.searchText)
                .textFieldStyle(.plain).focused($searchFocused)
                .onSubmit { if let first = model.searchMatches.first { model.reveal(first.id) } }
            if !model.searchText.isEmpty { Text("\(model.searchMatches.count) 项").font(.caption).foregroundStyle(.secondary) }
            Button { model.isSearchPresented = false; model.searchText = ""; model.request(.focus) } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain)
        }.padding(12).background(.background)
    }
    private var statusBar: some View {
        HStack(spacing: 10) {
            Text("\(model.document.nodeCount) 个主题")
            if model.isFocusMode {
                Button("退出专注") { model.toggleFocusMode() }.buttonStyle(.plain).foregroundStyle(model.document.theme.color)
            }
            if model.selectedIDs.count > 1 { Text("· 已选 \(model.selectedIDs.count) 项") }
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(workspace.saveStatus == "已保存" ? Color.secondary.opacity(0.5) : model.document.theme.color)
                    .frame(width: 4, height: 4)
                Text(workspace.saveStatus)
            }
            Rectangle().fill(InterfaceStyle.divider).frame(width: 1, height: 12).padding(.horizontal, 4)
            QuietIconButton(title: "缩小", symbol: "minus") { model.viewport.zoom(by: 1 / 1.15, at: .zero, in: .zero) }
            Text("\(Int((model.viewport.scale * 100).rounded()))%")
                .monospacedDigit().frame(width: 38)
            QuietIconButton(title: "放大", symbol: "plus") { model.viewport.zoom(by: 1.15, at: .zero, in: .zero) }
            QuietIconButton(title: "适应窗口（⌘0）", symbol: "arrow.up.left.and.arrow.down.right") { model.finishEditing?(); model.request(.fit) }
        }
        .font(.system(size: 10)).foregroundStyle(.secondary)
        .padding(.horizontal, 16).frame(height: 32).background(InterfaceStyle.panel)
    }
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { _ = workspace.showFolder(fileURL?.deletingLastPathComponent()) } label: { Label("资料库", systemImage: "chevron.left") }
                .help("保存并返回资料库（⌘[）")
            Button { model.showsOutline.toggle() } label: { Label("导航", systemImage: "sidebar.left") }
                .help("显示或隐藏大纲")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.finishEditing?(); model.undo() } label: { Label("撤销", systemImage: "arrow.uturn.backward") }
                .disabled(!model.canUndo).help("回退：\(model.undoName) · 可回退 \(model.undoCount) 步（⌘Z）")
            Button { model.finishEditing?(); model.redo() } label: { Label("重做", systemImage: "arrow.uturn.forward") }
                .disabled(!model.canRedo).help("前进：\(model.redoName) · 可前进 \(model.redoCount) 步（⇧⌘Z）")
            Menu {
                Section("可回退 \(model.undoCount) 步 · 可前进 \(model.redoCount) 步") {
                    Menu("回退到…") {
                        ForEach(Array(model.undoSteps.prefix(50).enumerated()), id: \.offset) { step in
                            Button("回退 \(step.offset + 1) 步 · \(step.element)") {
                                model.finishEditing?(); model.undo(steps: step.offset + 1)
                            }
                        }
                    }.disabled(!model.canUndo)
                    Menu("前进到…") {
                        ForEach(Array(model.redoSteps.prefix(50).enumerated()), id: \.offset) { step in
                            Button("前进 \(step.offset + 1) 步 · \(step.element)") {
                                model.finishEditing?(); model.redo(steps: step.offset + 1)
                            }
                        }
                    }.disabled(!model.canRedo)
                }
                Text("当前导图最多保留 400 步；菜单列出最近 50 步")
            } label: { Label("操作历史", systemImage: "clock.arrow.circlepath") }
                .help("操作历史：多步回退与前进")
            Menu {
                Button("添加子主题    Tab / ⌘K") { model.finishEditing?(); model.addChild() }
                Button("添加同级主题    ⇧⌘K") { model.finishEditing?(); model.addSibling() }
                Divider()
                Button("创建主题副本") { model.finishEditing?(); model.duplicateSelection() }
            } label: { Label("主题", systemImage: "plus") }
                .help("添加子主题：⌘K（画布中也可按 Tab）；添加同级主题：⇧⌘K")
            Menu {
                Section("布局") {
                    ForEach(MindMapLayout.allCases) { layout in
                        Button { model.finishEditing?(); model.changeLayout(layout) } label: {
                            Label(layout.label, systemImage: model.document.layout == layout ? "checkmark" : "square.grid.2x2")
                        }
                    }
                }
                Section("配色") {
                    ForEach(MapTheme.allCases) { theme in
                        Button { model.changeTheme(theme) } label: {
                            Label(theme.label, systemImage: model.document.theme == theme ? "checkmark" : "circle")
                        }
                    }
                }
                Divider()
                Button("从模板开始…") { model.finishEditing?(); model.showsTemplates = true }
            } label: { Label("外观", systemImage: "paintbrush") }
            Button {
                model.finishEditing?(); model.isSearchPresented.toggle()
                if model.isSearchPresented { model.showsOutline = true; model.sidebarSection = .outline }
            } label: { Label("查找", systemImage: "magnifyingglass") }.help("搜索主题（⌘F）")
            Button { model.showsInspector.toggle() } label: {
                Label("属性", systemImage: "sidebar.right")
            }.help("显示或隐藏主题属性")
            Menu {
                Section("导出") {
                    ForEach(ExportFormat.allCases) { format in
                        Button(format.label + "…") { model.finishEditing?(); ImportExportService.export(model.document, format: format, model: model) }
                    }
                }
                Divider()
                Button("导入文件…") { model.finishEditing?(); ImportExportService.importFile(into: model) }
                Button("命令面板…") { model.finishEditing?(); model.showsCommandPalette = true }
                Button(model.isFocusMode ? "退出专注模式" : "专注模式") { model.toggleFocusMode() }
            } label: { Label("文件与更多", systemImage: "ellipsis") }
        }
    }

}

private struct OutlineNodeRow: View {
    let node: MindMapNode
    @ObservedObject var model: EditorModel
    let depth: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Button { model.toggleCollapse(node.id) } label: {
                    Image(systemName: node.isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold)).frame(width: 13)
                }.buttonStyle(.plain).opacity(node.children.isEmpty ? 0 : 1).disabled(node.children.isEmpty)
                Image(systemName: depth == 0 ? "circle.inset.filled" : "circle.fill")
                    .font(.system(size: depth == 0 ? 11 : 5)).foregroundStyle(model.document.theme.color)
                Text(node.title.isEmpty ? "无标题" : node.title).font(.system(size: 12, weight: depth == 0 ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7).padding(.horizontal, 5).padding(.leading, CGFloat(min(depth, 8)) * 10)
            .background(model.selectedIDs.contains(node.id) ? model.document.theme.color.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .sidebarHoverFeedback(tint: model.document.theme.color)
            .contentShape(Rectangle())
            .onTapGesture { model.finishEditing?(); model.reveal(node.id); model.request(.focus) }
            .contextMenu {
                Button("添加子主题    Tab / ⌘K") { model.finishEditing?(); model.addChild(to: node.id) }
                Button("编辑文字    ⌘E / F2") { model.select(node.id); model.request(.editSelection) }
                Button("删除    Delete", role: .destructive) { model.select(node.id); model.deleteSelected() }.disabled(node.id == model.document.root.id)
            }
            if !node.isCollapsed {
                ForEach(node.children) { child in OutlineNodeRow(node: child, model: model, depth: depth + 1) }
            }
        }
    }
}
