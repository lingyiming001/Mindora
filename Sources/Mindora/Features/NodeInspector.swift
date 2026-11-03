import SwiftUI

struct NodeInspector: View {
    @ObservedObject var model: EditorModel
    @State private var tab: InspectorTab = .content
    private let colorOptions = ["6264D9", "4D91B8", "2C8A78", "C86B48", "AD6981", "657186"]
    private enum InspectorTab: String, CaseIterable {
        case content = "内容", style = "外观", task = "任务", canvas = "画布"
        var symbol: String {
            switch self { case .content: "text.alignleft"; case .style: "paintbrush.pointed"; case .task: "checklist"; case .canvas: "square.grid.2x2" }
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: tab.symbol).font(.system(size: 15, weight: .medium))
                    .foregroundStyle(model.document.theme.color)
                    .frame(width: 32, height: 32).background(model.document.theme.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 4) {
                    Text(tab == .canvas ? "画布设置" : "主题属性").font(.system(size: 14, weight: .semibold))
                    Text(tab == .canvas ? "布局与全图样式" : model.selectedIDs.count > 1 ? "已选择 \(model.selectedIDs.count) 个主题" : model.selectedNode?.id == model.document.root.id ? "中心主题" : "分支主题")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                QuietIconButton(title: "收起属性面板", symbol: "xmark") { model.showsInspector = false }
            }.padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 16)
            HStack(spacing: 4) {
                ForEach(InspectorTab.allCases, id: \.self) { item in
                    Button { tab = item } label: {
                        HStack(spacing: 5) {
                            Image(systemName: item.symbol).font(.system(size: 10, weight: .medium))
                            Text(item.rawValue).font(.system(size: 11, weight: tab == item ? .semibold : .regular))
                        }.frame(maxWidth: .infinity).frame(height: 30)
                            .foregroundStyle(tab == item ? model.document.theme.color : Color.secondary)
                            .background(tab == item ? model.document.theme.color.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain).accessibilityAddTraits(tab == item ? .isSelected : [])
                }
            }.padding(.horizontal, 16).padding(.bottom, 12)
            Divider()
            if let node = model.selectedNode {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if model.selectedIDs.count > 1 {
                            Label("已选 \(model.selectedIDs.count) 项 · 样式和任务批量应用", systemImage: "square.on.square")
                                .font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 3)
                        }
                        switch tab {
                        case .content:
                            titleEditor(node)
                            NodeRichContent(model: model, nodeID: node.id)
                            content(node)
                        case .style: style(node)
                        case .task: task(node)
                        case .canvas: canvasSettings
                        }
                    }.padding(.horizontal, 20).padding(.bottom, 20)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "cursorarrow.click").font(.system(size: 26, weight: .light)).foregroundStyle(.tertiary)
                    Text("选择一个主题").font(.system(size: 12, weight: .medium))
                    Text("在画布上选择主题后，可编辑内容和样式。")
                        .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(24).frame(maxHeight: .infinity)
            }
        }.onChange(of: model.inspectorContentRequest) { _, _ in tab = .content }
        .font(.system(size: 12)).tint(model.document.theme.color).background(InterfaceStyle.surface)
    }
    private var canvasSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            InspectorSection("结构与方向") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                    ForEach(MindMapLayout.allCases) { layout in
                        Button {
                            model.finishEditing?(); model.changeLayout(layout); model.request(.fit)
                        } label: {
                            VStack(spacing: 7) {
                                LayoutMiniature(layout: layout, tint: model.document.theme.color).frame(height: 42)
                                Text(layout.label).font(.system(size: 11))
                            }.frame(maxWidth: .infinity).padding(9)
                                .background(model.document.layout == layout ? model.document.theme.color.opacity(0.09) : InterfaceStyle.panel, in: RoundedRectangle(cornerRadius: 9))
                                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(model.document.layout == layout ? model.document.theme.color : InterfaceStyle.divider, lineWidth: model.document.layout == layout ? 1.5 : 0.5))
                        }.buttonStyle(.plain).accessibilityAddTraits(model.document.layout == layout ? .isSelected : [])
                    }
                }
            }
            InspectorSection("画布配色") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                    ForEach(MapTheme.allCases) { theme in
                        Button { model.finishEditing?(); model.changeTheme(theme) } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 3) {
                                    ForEach(Array(theme.branchColors.prefix(4).enumerated()), id: \.offset) { _, color in
                                        RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: color)).frame(height: 16)
                                    }
                                }
                                HStack { Text(theme.label); Spacer(); if model.document.theme == theme { Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.color) } }.font(.system(size: 11))
                            }.padding(10).background(InterfaceStyle.panel, in: RoundedRectangle(cornerRadius: 9))
                                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(model.document.theme == theme ? theme.color : InterfaceStyle.divider, lineWidth: model.document.theme == theme ? 1.5 : 0.5))
                        }.buttonStyle(.plain).accessibilityAddTraits(model.document.theme == theme ? .isSelected : [])
                    }
                }
                Text("配色作用于整个导图；单个主题的自定义颜色保持不变。").font(.caption2).foregroundStyle(.secondary)
            }
            InspectorSection("全图文字") {
                Text("修改会应用到全部主题（含折叠主题），并作为新增主题的默认值。未统一的项目显示推荐值，操作后统一；可用撤销恢复。")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("字号"); Spacer()
                    Stepper("\(Int(model.document.defaultNodeStyle?.fontSize ?? model.document.root.style?.fontSize ?? 14)) pt",
                            value: pageBinding(\.fontSize, fallback: model.document.root.style?.fontSize ?? 14), in: 10...36, step: 1).fixedSize()
                }
                Picker("对齐", selection: pageBinding(\.textAlignment, fallback: .center)) {
                    ForEach(NodeTextAlignment.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
                HStack {
                    Toggle("粗体", isOn: pageBinding(\.bold, fallback: false))
                    Toggle("斜体", isOn: pageBinding(\.italic, fallback: false))
                }.toggleStyle(.button)
                Picker("垂直对齐", selection: pageBinding(\.verticalAlignment, fallback: .center)) {
                    ForEach(NodeVerticalAlignment.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented)
                HStack {
                    Toggle("下划线", isOn: pageBinding(\.underline, fallback: false))
                    Toggle("删除线", isOn: pageBinding(\.strikethrough, fallback: false))
                }.toggleStyle(.button)
                pageColor("文字颜色", keyPath: \.textColorHex, fallback: "303444")
            }
            InspectorSection("全图主题样式") {
                Picker("外形", selection: pageBinding(\.cornerRadius, fallback: 12)) {
                    Text("直角").tag(0.0); Text("圆角").tag(12.0); Text("大圆角").tag(28.0)
                    if let radius = model.document.defaultNodeStyle?.cornerRadius, ![0.0, 12.0, 28.0].contains(radius) { Text("自定义").tag(radius) }
                }.pickerStyle(.segmented)
                Picker("边框", selection: pageBinding(\.borderWidth, fallback: 1)) {
                    ForEach(0...6, id: \.self) { Text($0 == 0 ? "无边框" : "\($0) pt").tag(Double($0)) }
                }
                pageColor("边框颜色", keyPath: \.borderColorHex, fallback: "6264D9")
                InspectorSwitch("虚线边框", isOn: pageBinding(\.dashedBorder, fallback: false))
                InspectorSwitch("显示阴影", isOn: pageBinding(\.shadow, fallback: true))
                pageColor("背景颜色", keyPath: \.backgroundHex, fallback: "FFFFFF")
            }
            InspectorSection("视图") {
                Button("适应窗口", systemImage: "arrow.up.left.and.arrow.down.right") { model.finishEditing?(); model.request(.fit) }
                Button("定位当前主题", systemImage: "scope") { model.finishEditing?(); model.request(.centerSelection) }
            }
        }
    }
    private func pageBinding<T>(_ keyPath: WritableKeyPath<NodeStyle, T?>, fallback: T) -> Binding<T> {
        Binding(get: { model.document.defaultNodeStyle?[keyPath: keyPath] ?? fallback }, set: { model.setPageStyle(keyPath, value: $0) })
    }
    private func pageColor(_ title: String, keyPath: WritableKeyPath<NodeStyle, String?>, fallback: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            ColorPicker(title, selection: Binding(get: {
            Color(nsColor: NSColor(hex: model.document.defaultNodeStyle?[keyPath: keyPath] ?? fallback) ?? .labelColor)
        }, set: { color in
            guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
            let hex = String(format: "%02X%02X%02X", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
            model.setPageStyle(keyPath, value: hex)
        }), supportsOpacity: false).labelsHidden()
        }
    }
    private func titleEditor(_ node: MindMapNode) -> some View {
        InspectorSection("主题文字") {
            TextField("输入主题…", text: binding(node, key: "title", get: { $0.title }, set: { $0.title = $1 }), axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 13, weight: .medium)).lineLimit(2...5)
                .padding(10).background(InterfaceStyle.panel.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        }
    }
    @ViewBuilder private func content(_ node: MindMapNode) -> some View {
        InspectorSection("备注") {
            DisclosureGroup(node.note.isEmpty ? "添加备注" : "编辑备注 · \(node.note.count) 字") {
                TextEditor(text: binding(node, key: "note", get: { $0.note }, set: { $0.note = $1 }))
                    .font(.system(size: 12)).scrollContentBackground(.hidden).frame(height: 90)
            }.font(.system(size: 12))
        }
        InspectorSection("标签") {
            TextField("用逗号分隔", text: binding(node, key: "tags", get: { $0.tags.joined(separator: ", ") }, set: { value, text in
                value.tags = text.replacingOccurrences(of: "，", with: ",").components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            })).textFieldStyle(.plain).font(.system(size: 12))
            if !node.tags.isEmpty {
                Text(node.tags.map { "#" + $0 }.joined(separator: "  ")).font(.system(size: 10)).foregroundStyle(model.document.theme.color)
            }
        }
    }
    @ViewBuilder private func style(_ node: MindMapNode) -> some View {
        InspectorSection("文字排版") {
            InspectorChoices(title: "水平对齐", selection: styleBinding(node, \.textAlignment, fallback: .center), options: NodeTextAlignment.allCases, label: { $0.label }, tint: model.document.theme.color)
            HStack {
                Text("字号"); Spacer()
                Stepper("\(Int(node.style?.fontSize ?? (node.id == model.document.root.id ? 17 : 14))) pt",
                        value: styleBinding(node, \.fontSize, fallback: node.id == model.document.root.id ? 17 : 14), in: 10...36, step: 1)
                    .fixedSize()
            }
            HStack(spacing: 6) {
                Toggle(isOn: styleBinding(node, \.bold, fallback: false)) { Image(systemName: "bold").frame(width: 26) }.help("粗体")
                Toggle(isOn: styleBinding(node, \.italic, fallback: false)) { Image(systemName: "italic").frame(width: 26) }.help("斜体")
                Toggle(isOn: styleBinding(node, \.underline, fallback: false)) { Image(systemName: "underline").frame(width: 26) }.help("下划线")
                Toggle(isOn: styleBinding(node, \.strikethrough, fallback: false)) { Image(systemName: "strikethrough").frame(width: 26) }.help("删除线")
            }.toggleStyle(.button).controlSize(.small)
            HStack {
                Text("垂直对齐").foregroundStyle(.secondary)
                Spacer()
                InspectorChoices(title: "垂直对齐", selection: styleBinding(node, \.verticalAlignment, fallback: .center), options: NodeVerticalAlignment.allCases, label: { $0.label }, tint: model.document.theme.color).frame(width: 170)
            }
            colorPicker("文字颜色", node: node, keyPath: \.textColorHex, fallback: node.id == model.document.root.id ? "FFFFFF" : "303444")
        }
        InspectorSection("主题尺寸") {
            InspectorSwitch("自动适应文字宽度", isOn: Binding(get: { node.style?.width == nil }, set: { automatic in
                model.updateSelectedProperties("调整主题宽度") { value in
                    var style = value.style ?? NodeStyle()
                    if automatic { style.width = nil }
                    else if style.width == nil { style.width = max(160, Double(LayoutEngine.titleSize(node, isRoot: node.id == model.document.root.id).width)) }
                    value.style = style
                }
            }))
            if node.style?.width != nil {
                HStack {
                    Text("宽度"); Spacer()
                    Stepper("\(Int(node.style?.width ?? 310)) pt", value: styleBinding(node, \.width, fallback: 310), in: 160...1200, step: 10).fixedSize()
                }
                Slider(value: styleBinding(node, \.width, fallback: 310), in: 160...1200, step: 1).accessibilityLabel("主题宽度")
            }
            Divider()
            InspectorSwitch("自动适应文字高度", isOn: Binding(get: { node.style?.height == nil }, set: { automatic in
                model.updateSelectedProperties("调整主题高度") {
                    var style = $0.style ?? NodeStyle()
                    style.height = automatic ? nil : Double(model.layoutResult.frames[node.id]?.height ?? 80)
                    if let height = style.height { style.height = min(2400, max(44, height)) }
                    $0.style = style
                }
            }))
            if node.style?.height != nil {
                Stepper("最小高度：\(Int(node.style?.height ?? 80)) pt", value: styleBinding(node, \.height, fallback: 80), in: 44...2400, step: 10)
            }
            Text("画布底角可同时拉伸宽高。手动尺寸随文件保存；高度不足以显示全文时会自动撑开，避免截断。")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        InspectorSection("节点外观") {
            Text("主题色").foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(colorOptions, id: \.self) { hex in
                    Button {
                        model.updateSelectedProperties("更改主题色") {
                            var style = $0.style ?? NodeStyle(); style.colorHex = hex; $0.style = style
                        }
                    } label: {
                        Circle().fill(Color(nsColor: NSColor(hex: hex)!)).frame(width: 27, height: 27)
                            .overlay { if node.style?.colorHex == hex { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white) } }
                    }.buttonStyle(.plain).accessibilityLabel("主题色 \(hex)")
                }
            }
            colorPicker("自定义主题色", node: node, keyPath: \.colorHex, fallback: "6264D9")
            Divider()
            colorPicker("背景颜色", node: node, keyPath: \.backgroundHex, fallback: node.id == model.document.root.id ? "6264D9" : "FFFFFF")
            HStack {
                Text("边框"); Spacer()
                Picker("边框粗细", selection: styleBinding(node, \.borderWidth, fallback: 1)) {
                    ForEach(0...6, id: \.self) { Text($0 == 0 ? "无边框" : "\($0) pt").tag(Double($0)) }
                }.labelsHidden().frame(width: 110)
            }
            colorPicker("边框颜色", node: node, keyPath: \.borderColorHex, fallback: node.style?.colorHex ?? "6264D9")
            InspectorSwitch("虚线边框", isOn: styleBinding(node, \.dashedBorder, fallback: false))
            HStack {
                Text("圆角"); Spacer()
                Stepper("\(Int(node.style?.cornerRadius ?? (node.id == model.document.root.id ? 15 : 11))) pt",
                        value: styleBinding(node, \.cornerRadius, fallback: node.id == model.document.root.id ? 15 : 11), in: 0...28, step: 1).fixedSize()
            }
            InspectorSwitch("显示阴影", isOn: styleBinding(node, \.shadow, fallback: true))
        }
        Button {
            let defaults = model.document.defaultNodeStyle
            model.updateSelectedProperties("恢复默认样式") { $0.style = defaults }
        } label: { Label("恢复所选主题默认样式", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity) }
            .buttonStyle(.bordered).controlSize(.regular)
    }
    @ViewBuilder private func task(_ node: MindMapNode) -> some View {
        InspectorSection("优先级") {
            InspectorChoices(title: "优先级", selection: taskBinding(node, get: { $0.priority }, set: { $0.priority = $1 }), options: [0, 1, 2, 3], label: { ["无", "高", "中", "低"][$0] }, tint: model.document.theme.color)
            Text("高 P1 · 中 P2 · 低 P3").font(.caption).foregroundStyle(.secondary)
        }
        InspectorSection("任务进度") {
            InspectorSwitch("启用任务进度", isOn: taskBinding(node, get: { $0.progress != nil }, set: { $0.progress = $1 ? ($0.progress ?? 0) : nil }))
            if let progress = node.progress {
                HStack {
                    Text(progress == 100 ? "已完成" : progress == 0 ? "未开始" : "进行中").foregroundStyle(.secondary)
                    Spacer()
                    Text("\(progress)%").font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                }
                Slider(value: taskBinding(node, key: "progress", get: { Double($0.progress ?? 0) }, set: { $0.progress = Int($1) }), in: 0...100, step: 1)
                    .accessibilityLabel("完成进度")
                HStack(spacing: 6) {
                    ForEach([0, 25, 50, 75, 100], id: \.self) { value in
                        Button("\(value)%") { model.updateSelectedProperties("设置进度") { $0.progress = value } }
                            .buttonStyle(.bordered).controlSize(.mini)
                    }
                }
            }
        }
        InspectorSection("负责人") {
            TextField("输入姓名或团队", text: taskBinding(node, key: "assignee", get: { $0.assignee }, set: { $0.assignee = $1 }))
                .textFieldStyle(.roundedBorder)
        }
        InspectorSection("计划与截止") {
            taskDate("开始日期", node: node, keyPath: \.startDate)
            taskDate("截止日期", node: node, keyPath: \.dueDate)
            if let due = node.dueDate, due < Calendar.current.startOfDay(for: Date()), node.progress != 100 {
                Label("任务已逾期", systemImage: "clock.badge.exclamationmark").font(.caption).foregroundStyle(.orange)
            }
        }
        Button {
            model.updateSelectedProperties("清除任务信息") { $0.priority = 0; $0.progress = nil; $0.assignee = ""; $0.startDate = nil; $0.dueDate = nil }
        } label: { Label("清除所选主题任务信息", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity) }
            .buttonStyle(.bordered)
    }
    private func taskDate(_ title: String, node: MindMapNode, keyPath: WritableKeyPath<NodeProperties, Date?>) -> some View {
        let value = NodeProperties(model.document.root.find(node.id) ?? node)[keyPath: keyPath]
        return VStack(alignment: .leading, spacing: 8) {
            InspectorSwitch(title, isOn: Binding(get: { value != nil }, set: { enabled in
                model.updateSelectedProperties("设置" + title) { properties in
                    properties[keyPath: keyPath] = enabled ? Calendar.current.startOfDay(for: Date()) : nil
                    if let start = properties.startDate, let due = properties.dueDate, start > due {
                        if keyPath == \.startDate { properties.dueDate = start } else { properties.startDate = due }
                    }
                }
            }))
            if let value {
                DatePicker(title, selection: Binding(get: { value }, set: { date in
                    model.updateSelectedProperties("设置" + title) { properties in
                        properties[keyPath: keyPath] = Calendar.current.startOfDay(for: date)
                        if let start = properties.startDate, let due = properties.dueDate, start > due {
                            if keyPath == \.startDate { properties.dueDate = start } else { properties.startDate = due }
                        }
                    }
                }), displayedComponents: .date).labelsHidden().datePickerStyle(.field)
            }
        }
    }

    private func styleBinding<T>(_ node: MindMapNode, _ keyPath: WritableKeyPath<NodeStyle, T?>, fallback: T) -> Binding<T> {
        Binding(get: { (model.document.root.find(node.id) ?? node).style?[keyPath: keyPath] ?? fallback }, set: { value in
            model.updateSelectedProperties("修改样式", key: "style.\(String(describing: keyPath))") {
                var style = $0.style ?? NodeStyle(); style[keyPath: keyPath] = value; $0.style = style
            }
        })
    }
    private func taskBinding<T>(_ node: MindMapNode, key: String? = nil, get: @escaping (MindMapNode) -> T,
                                set: @escaping (inout NodeProperties, T) -> Void) -> Binding<T> {
        Binding(get: { get(model.document.root.find(node.id) ?? node) }, set: { value in
            model.updateSelectedProperties("修改任务", key: key) { set(&$0, value) }
        })
    }
    private func colorPicker(_ title: String, node: MindMapNode, keyPath: WritableKeyPath<NodeStyle, String?>, fallback: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            ColorPicker(title, selection: Binding(get: {
            let hex = (model.document.root.find(node.id) ?? node).style?[keyPath: keyPath] ?? fallback
            return Color(nsColor: NSColor(hex: hex) ?? .labelColor)
        }, set: { color in
            guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
            let hex = String(format: "%02X%02X%02X", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
            model.updateSelectedProperties("修改颜色", key: "color.\(String(describing: keyPath))") {
                var style = $0.style ?? NodeStyle(); style[keyPath: keyPath] = hex; $0.style = style
            }
        }), supportsOpacity: false).labelsHidden()
        }
    }
    private func binding<T>(_ node: MindMapNode, key: String? = nil, get: @escaping (MindMapNode) -> T,
                            set: @escaping (inout NodeProperties, T) -> Void) -> Binding<T> {
        Binding(get: { get(model.document.root.find(node.id) ?? node) }, set: { value in model.updateNode(node.id, key: key) { set(&$0, value) } })
    }
}


private struct LayoutMiniature: View {
    let layout: MindMapLayout
    let tint: Color
    var body: some View {
        Canvas { context, size in
            let root: CGPoint
            let leaves: [CGPoint]
            switch layout {
            case .balanced:
                root = CGPoint(x: 0.5, y: 0.5); leaves = [CGPoint(x: 0.12, y: 0.2), CGPoint(x: 0.12, y: 0.8), CGPoint(x: 0.88, y: 0.2), CGPoint(x: 0.88, y: 0.8)]
            case .rightTree:
                root = CGPoint(x: 0.18, y: 0.5); leaves = [CGPoint(x: 0.82, y: 0.2), CGPoint(x: 0.82, y: 0.8)]
            case .leftTree:
                root = CGPoint(x: 0.82, y: 0.5); leaves = [CGPoint(x: 0.18, y: 0.2), CGPoint(x: 0.18, y: 0.8)]
            case .organization:
                root = CGPoint(x: 0.5, y: 0.15); leaves = [CGPoint(x: 0.15, y: 0.85), CGPoint(x: 0.5, y: 0.85), CGPoint(x: 0.85, y: 0.85)]
            }
            func point(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size.width, y: p.y * size.height) }
            for leaf in leaves {
                var line = Path(); line.move(to: point(root)); line.addLine(to: point(leaf))
                context.stroke(line, with: .color(tint.opacity(0.4)), lineWidth: 1)
            }
            for (index, p) in ([root] + leaves).enumerated() {
                let center = point(p)
                context.fill(Path(roundedRect: CGRect(x: center.x - 9, y: center.y - 4, width: 18, height: 8), cornerRadius: 3), with: .color(index == 0 ? tint : tint.opacity(0.25)))
            }
        }.accessibilityHidden(true)
    }
}
