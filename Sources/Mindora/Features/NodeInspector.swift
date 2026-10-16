import SwiftUI

struct NodeInspector: View {
    @ObservedObject var model: EditorModel
    @State private var tab: InspectorTab = .content
    private let colorOptions = ["6264D9", "4D91B8", "2C8A78", "C86B48", "AD6981", "657186"]
    private enum InspectorTab: String, CaseIterable {
        case content = "内容", style = "样式", task = "任务", canvas = "画布"
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(tab == .canvas ? "画布样式" : "主题属性").font(.system(size: 14, weight: .semibold))
                Spacer()
                QuietIconButton(title: "收起属性面板", symbol: "xmark") { model.showsInspector = false }
            }.padding(.leading, 16).padding(.trailing, 9).frame(height: 45)
            Picker("属性分组", selection: $tab) {
                ForEach(InspectorTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 14).padding(.bottom, 14)
            Divider()
            if let node = model.selectedNode {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
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
                    }.padding(12)
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
        .font(.system(size: 12)).tint(model.document.theme.color).background(InterfaceStyle.panel)
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
                Picker("对齐", selection: pageBinding(\.textAlignment, fallback: .left)) {
                    ForEach(NodeTextAlignment.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
                HStack {
                    Toggle("粗体", isOn: pageBinding(\.bold, fallback: false))
                    Toggle("斜体", isOn: pageBinding(\.italic, fallback: false))
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
                Toggle("显示阴影", isOn: pageBinding(\.shadow, fallback: true)).toggleStyle(.switch).controlSize(.small)
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
        ColorPicker(title, selection: Binding(get: {
            Color(nsColor: NSColor(hex: model.document.defaultNodeStyle?[keyPath: keyPath] ?? fallback) ?? .labelColor)
        }, set: { color in
            guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
            let hex = String(format: "%02X%02X%02X", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
            model.setPageStyle(keyPath, value: hex)
        }), supportsOpacity: false)
    }
    private func titleEditor(_ node: MindMapNode) -> some View {
        InspectorSection("主题文字") {
            TextField("输入主题…", text: binding(node, key: "title", get: { $0.title }, set: { $0.title = $1 }), axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 13, weight: .medium)).lineLimit(1...4)
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
            Picker("文字对齐", selection: styleBinding(node, \.textAlignment, fallback: .center)) {
                ForEach(NodeTextAlignment.allCases) { alignment in
                    Label(alignment.label, systemImage: alignment.symbol).tag(alignment)
                }
            }.pickerStyle(.segmented).labelsHidden().help("调整主题标题的对齐方式，多选时批量应用")
            HStack {
                Text("字号"); Spacer()
                Stepper("\(Int(node.style?.fontSize ?? (node.id == model.document.root.id ? 17 : 14))) pt",
                        value: styleBinding(node, \.fontSize, fallback: node.id == model.document.root.id ? 17 : 14), in: 10...36, step: 1)
                    .fixedSize()
            }
            HStack(spacing: 10) {
                Toggle("粗体", isOn: styleBinding(node, \.bold, fallback: false))
                Toggle("斜体", isOn: styleBinding(node, \.italic, fallback: false))
            }.toggleStyle(.button).controlSize(.regular)
            colorPicker("文字颜色", node: node, keyPath: \.textColorHex, fallback: node.id == model.document.root.id ? "FFFFFF" : "303444")
        }
        InspectorSection("主题尺寸") {
            Toggle("自动适应原文", isOn: Binding(get: { node.style?.width == nil }, set: { automatic in
                model.updateSelectedProperties("调整主题宽度") { value in
                    var style = value.style ?? NodeStyle()
                    if automatic { style.width = nil }
                    else if style.width == nil { style.width = max(160, Double(LayoutEngine.titleSize(node, isRoot: node.id == model.document.root.id).width)) }
                    value.style = style
                }
            })).toggleStyle(.switch).controlSize(.small)
            if node.style?.width != nil {
                HStack {
                    Text("宽度"); Spacer()
                    Stepper("\(Int(node.style?.width ?? 310)) pt", value: styleBinding(node, \.width, fallback: 310), in: 160...1200, step: 10).fixedSize()
                }
                Slider(value: styleBinding(node, \.width, fallback: 310), in: 160...1200, step: 1).accessibilityLabel("主题宽度")
            }
            Divider()
            Toggle("自动适应高度", isOn: Binding(get: { node.style?.height == nil }, set: { automatic in
                model.updateSelectedProperties("调整主题高度") {
                    var style = $0.style ?? NodeStyle()
                    style.height = automatic ? nil : Double(model.layoutResult.frames[node.id]?.height ?? 80)
                    if let height = style.height { style.height = min(2400, max(44, height)) }
                    $0.style = style
                }
            })).toggleStyle(.switch).controlSize(.small)
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
            HStack {
                Text("圆角"); Spacer()
                Stepper("\(Int(node.style?.cornerRadius ?? (node.id == model.document.root.id ? 15 : 11))) pt",
                        value: styleBinding(node, \.cornerRadius, fallback: node.id == model.document.root.id ? 15 : 11), in: 0...28, step: 1).fixedSize()
            }
            Toggle("显示阴影", isOn: styleBinding(node, \.shadow, fallback: true)).toggleStyle(.switch).controlSize(.small)
        }
        Button {
            let defaults = model.document.defaultNodeStyle
            model.updateSelectedProperties("恢复默认样式") { $0.style = defaults }
        } label: { Label("恢复所选主题默认样式", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity) }
            .buttonStyle(.bordered).controlSize(.regular)
    }
    @ViewBuilder private func task(_ node: MindMapNode) -> some View {
        InspectorSection("优先级") {
            Picker("优先级", selection: taskBinding(node, get: { $0.priority }, set: { $0.priority = $1 })) {
                Text("无").tag(0); Text("高").tag(1); Text("中").tag(2); Text("低").tag(3)
            }.pickerStyle(.segmented).labelsHidden()
            Text("高 P1 · 中 P2 · 低 P3").font(.caption).foregroundStyle(.secondary)
        }
        InspectorSection("任务进度") {
            Toggle("作为任务跟踪", isOn: taskBinding(node, get: { $0.progress != nil }, set: { $0.progress = $1 ? ($0.progress ?? 0) : nil }))
                .toggleStyle(.switch).controlSize(.small)
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
        Button {
            model.updateSelectedProperties("清除任务信息") { $0.priority = 0; $0.progress = nil }
        } label: { Label("清除所选主题任务信息", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity) }
            .buttonStyle(.bordered)
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
        ColorPicker(title, selection: Binding(get: {
            let hex = (model.document.root.find(node.id) ?? node).style?[keyPath: keyPath] ?? fallback
            return Color(nsColor: NSColor(hex: hex) ?? .labelColor)
        }, set: { color in
            guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
            let hex = String(format: "%02X%02X%02X", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
            model.updateSelectedProperties("修改颜色", key: "color.\(String(describing: keyPath))") {
                var style = $0.style ?? NodeStyle(); style[keyPath: keyPath] = hex; $0.style = style
            }
        }), supportsOpacity: false)
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
