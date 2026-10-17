import AppKit

@MainActor enum AIAppTools {
    private static var documentReadSnapshot: MindMapDocument?
    static let commands = ["new_map", "save", "save_copy", "library", "undo", "redo", "add_child", "add_sibling", "delete_nodes", "duplicate_nodes", "copy", "paste", "cut", "collapse", "move_up", "move_down", "select_all", "fit", "center", "focus", "outline", "inspector", "templates", "apply_template", "theme", "layout", "search", "command_palette", "edit_text", "insert_link", "insert_code", "insert_image", "insert_file", "export_attachment", "remove_attachment", "import", "export", "backup", "settings", "recycle_bin", "shortcuts", "choose_library", "choose_backup", "open_file"]
    static var definitions: [[String: Any]] {
        [tool("mindora_state", "读取应用状态、文档标识及可用命令。操作前先调用。", [:]),
         tool("mindora_document", "读取当前导图全部内容（附件仅元数据）。需要用户启用共享导图。", [:]),
         tool("mindora_edit_node", "修改主题文字、备注、标签、代码、链接、任务属性和样式。fields_json 是 MindMapNode 字段 JSON 对象，不能修改 id/children/attachments。可撤销。", ["node_id": string("主题 UUID"), "fields_json": string("如 {\"title\":\"标题\",\"link\":\"https://example.com\",\"style\":{\"fontSize\":18,\"textAlignment\":\"left\"}}")], required: ["node_id", "fields_json"]),
         tool("mindora_page_style", "批量更新当前页面所有主题及新主题默认样式。只修改提供的字段。", ["style_json": string("NodeStyle JSON，可含 fontSize、textAlignment(left/center/right)、bold、italic、width、height、colorHex、textColorHex、backgroundHex、borderWidth、cornerRadius")], required: ["style_json"]),
         tool("mindora_add_nodes", "在父主题下批量添加子主题，可撤销。", ["parent_id": string("父主题 UUID"), "titles": ["type": "array", "items": ["type": "string"], "maxItems": 100]], required: ["parent_id", "titles"]),
         tool("mindora_replace_document", "替换导图结构、全局样式、布局、主题及全部节点。先读 mindora_document。document_json 为完整 MindMapDocument，须保留现有文档 id 和附件 id；保留附件的二进制数据由客户端恢复。一次撤销可恢复。", ["document_json": string("完整导图 JSON")], required: ["document_json"]),
         tool("mindora_command", "调用应用原生命令。可选 node_id 先选择主题。导出、导入、文件选择和另存为会打开原生面板，需用户完成。export 的 value 可为 markdown/opml/json/svg/png/jpeg/pdf；apply_template、theme、layout 的 value 用 mindora_state 返回的对应 id；search 的 value 为查询。", ["action": ["type": "string", "enum": commands], "node_id": string("可选主题 UUID"), "value": string("可选参数；附件导出/删除传附件 UUID")], required: ["action"]),
         tool("mindora_library", "管理当前工作空间内文件与回收箱。path 和 destination 为资料库内相对路径。rename 打开原生重命名面板。move 可用目标文件夹路径或 workspace_id。", ["action": ["type": "string", "enum": ["list", "open", "new_folder", "rename", "move", "duplicate", "trash", "favorite", "import", "recycle_list", "restore", "delete_permanently", "empty_recycle"]], "path": string("相对路径"), "destination": string("移动到相对文件夹"), "workspace_id": string("移动到其他工作空间的 UUID"), "item_id": string("回收箱项目 UUID")], required: ["action"]),
         tool("mindora_workspace", "管理工作空间。remove 仅移除登记并保留磁盘数据，由原生面板确认。", ["action": ["type": "string", "enum": ["list", "create", "switch", "update", "remove"]], "id": string("空间 UUID"), "name": string("名称"), "symbol": string("SF Symbol 名称"), "icon_text": string("最多两个字符"), "introduction": string("最多500字"), "color": string("六位十六进制色值")], required: ["action"]),
         tool("mindora_preferences", "读取/更新常规、外观、默认导图和备份设置。仅支持已列出的应用偏好；模型密钥与权限不可由 AI 修改。", ["values_json": string("省略时读取，传入偏好 JSON 时更新")])]
    }
    static func isReadOnly(_ name: String, _ args: [String: Any]) -> Bool {
        if ["mindora_state", "mindora_document"].contains(name) { return true }
        if name == "mindora_preferences" { return args["values_json"] == nil }
        return ["mindora_library", "mindora_workspace"].contains(name) && ["list", "recycle_list"].contains(args["action"] as? String ?? "")
    }
    static func requiresConfirmation(_ name: String, _ args: [String: Any]) -> Bool {
        ["delete_permanently", "empty_recycle", "remove", "trash", "cut", "delete_nodes"].contains(args["action"] as? String ?? "")
    }
    static func execute(_ name: String, _ args: [String: Any], openWindow: (String) -> Void) throws -> String {
        try Task.checkCancellation()
        let workspace = WorkspaceStore.shared, library = LibraryStore.shared
        // Commit the inline editor before reading or modifying its backing model.
        workspace.editor?.finishEditing?()
        library.errorMessage = nil; workspace.errorMessage = nil; workspace.editor?.errorMessage = nil
        func editor() throws -> EditorModel {
            guard let model = workspace.editor else { throw AIError.message("请先打开或创建导图") }; return model
        }
        var result: Any = ["status": "completed"]
        switch name {
        case "mindora_state":
            result = ["document_id": workspace.editor?.document.id.uuidString ?? "", "selected_node_id": workspace.editor?.selectedID?.uuidString ?? "", "node_count": workspace.editor?.document.nodeCount ?? 0, "workspace_id": WorkspaceCatalog.shared.current(library.rootURL)?.id.uuidString ?? "", "commands": commands, "templates": MapTemplate.allCases.map { ["id": $0.id, "title": $0.title] }, "themes": MapTheme.allCases.map { ["id": $0.id, "title": $0.label] }, "layouts": MindMapLayout.allCases.map { ["id": $0.id, "title": $0.label] }, "document_sharing_enabled": AIConfiguration.shared.sharesDocument]
        case "mindora_document":
            guard AIConfiguration.shared.sharesDocument else { throw AIError.message("用户尚未启用“共享当前导图”，请提示用户手动开启。") }
            let map = try editor().document
            documentReadSnapshot = map
            return try documentJSON(map)
        case "mindora_edit_node":
            let model = try editor(), id = try uuid(args, "node_id")
            guard let node = model.document.root.find(id) else { throw AIError.message("主题不存在") }
            var fields = try AIJSON.object(Data(try text(args, "fields_json").utf8))
            for key in ["id", "children", "attachments"] { guard fields[key] == nil else { throw AIError.message("此操作不允许修改 \(key)") } }
            var object = try AIJSON.object(JSONEncoder().encode(node))
            if let patch = fields["style"] as? [String: Any] {
                var style = object["style"] as? [String: Any] ?? [:]
                for (key, value) in patch { style[key] = value }
                fields["style"] = style
            }
            for (key, value) in fields { object[key] = value }
            fields.removeAll()
            let updated = try JSONDecoder().decode(MindMapNode.self, from: JSONSerialization.data(withJSONObject: object))
            var map = model.document
            _ = map.nodes[0].update(id) { $0 = updated }
            try map.validate(); model.replaceDocument(map, name: "AI 修改主题")
        case "mindora_page_style":
            let model = try editor(), patch = try AIJSON.object(Data(try text(args, "style_json").utf8))
            let keys: Set<String> = ["fontSize", "textAlignment", "bold", "italic", "width", "height", "colorHex", "textColorHex", "backgroundHex", "borderWidth", "cornerRadius"]
            guard !patch.isEmpty, Set(patch.keys).isSubset(of: keys) else { throw AIError.message("无效的页面样式字段") }
            func merge(_ existing: NodeStyle?) throws -> NodeStyle {
                var object = try AIJSON.object(JSONEncoder().encode(existing ?? NodeStyle()))
                for (key, value) in patch { object[key] = value }
                return try JSONDecoder().decode(NodeStyle.self, from: JSONSerialization.data(withJSONObject: object))
            }
            var map = model.document; map.defaultNodeStyle = try merge(map.defaultNodeStyle)
            func style(_ node: inout MindMapNode) throws {
                node.style = try merge(node.style)
                for i in node.children.indices { try style(&node.children[i]) }
            }
            try style(&map.nodes[0]); try map.validate(); model.replaceDocument(map, name: "AI 设置全图样式")
        case "mindora_add_nodes":
            let model = try editor(), id = try uuid(args, "parent_id")
            guard model.document.root.find(id) != nil, let titles = args["titles"] as? [String], !titles.isEmpty, titles.count <= 100 else { throw AIError.message("父主题无效或子主题数量超限") }
            var map = model.document; let children = titles.map { title -> MindMapNode in
                var node = MindMapNode(title: title); node.style = map.defaultNodeStyle ?? node.style; return node
            }
            _ = map.nodes[0].update(id) { $0.children += children; $0.isCollapsed = false }
            try map.validate(); model.replaceDocument(map, name: "AI 添加主题")
            result = ["created_ids": children.map { $0.id.uuidString }]
        case "mindora_replace_document":
            let model = try editor()
            guard documentReadSnapshot == model.document else { throw AIError.message("导图自上次读取后已变化，请先重新调用 mindora_document 再替换，避免覆盖最新编辑") }
            var map = try JSONDecoder().decode(MindMapDocument.self, from: Data(try text(args, "document_json").utf8))
            guard map.id == model.document.id else { throw AIError.message("目标文档已变化，请重新读取当前导图") }
            try map.validate()
            let existing = Dictionary(uniqueKeysWithValues: model.document.allNodes.map { ($0.id, $0.attachments) })
            let allAttachments = model.document.allNodes.flatMap(\.attachments)
            func restore(_ node: inout MindMapNode) throws {
                node.attachments = try node.attachments.map { attachment in
                    if let original = existing[node.id]?.first(where: { $0.id == attachment.id }) { return original }
                    let matches = allAttachments.filter { $0.id == attachment.id }
                    guard matches.count == 1, let original = matches.first else { throw AIError.message("附件标识无效，请保留原主题和附件 ID；新增附件请使用原生文件面板") }
                    return original
                }
                for i in node.children.indices { try restore(&node.children[i]) }
            }
            try restore(&map.nodes[0]); try map.validate(); model.replaceDocument(map, name: "AI 更新导图")
        case "mindora_command":
            let action = try text(args, "action")
            if let raw = args["node_id"] as? String {
                let id = try uuid(["id": raw], "id"), model = try editor()
                guard model.document.root.find(id) != nil else { throw AIError.message("主题不存在") }; model.select(id)
            }
            switch action {
            case "new_map": library.newMap()
            case "save": try workspace.saveActive()
            case "save_copy": workspace.save(asCopy: true)
            case "library": guard workspace.showFolder() else { throw AIError.message(workspace.errorMessage ?? "保存失败") }
            case "settings": openWindow("settings")
            case "recycle_bin": openWindow("recycle-bin")
            case "shortcuts": openWindow("shortcuts")
            case "choose_library": library.chooseLocation()
            case "choose_backup": BackupStore.shared.chooseFolder()
            case "open_file": workspace.chooseFile()
            default:
                let model = try editor()
                switch action {
                case "undo": model.undo()
                case "redo": model.redo()
                case "add_child": model.addChild()
                case "add_sibling": model.addSibling()
                case "delete_nodes": model.deleteSelected()
                case "duplicate_nodes": model.duplicateSelection()
                case "copy": model.copySelection()
                case "paste": model.paste()
                case "cut": model.cutSelection()
                case "collapse": model.toggleCollapse()
                case "move_up": model.reorderSelected(by: -1)
                case "move_down": model.reorderSelected(by: 1)
                case "select_all": model.selectAll()
                case "fit": model.request(.fit)
                case "center": model.request(.centerSelection)
                case "focus": model.toggleFocusMode()
                case "outline": model.showsOutline.toggle()
                case "inspector": model.showsInspector.toggle()
                case "templates": model.showsTemplates = true
                case "apply_template":
                    guard let template = MapTemplate(rawValue: args["value"] as? String ?? "") else { throw AIError.message("模板不存在") }
                    var map = template.document; map.id = model.document.id
                    model.replaceDocument(map, name: "AI 应用模板")
                case "theme":
                    guard let theme = MapTheme(rawValue: args["value"] as? String ?? "") else { throw AIError.message("主题不存在") }; model.changeTheme(theme)
                case "layout":
                    guard let layout = MindMapLayout(rawValue: args["value"] as? String ?? "") else { throw AIError.message("布局不存在") }; model.changeLayout(layout)
                case "search": model.showsOutline = true; model.isSearchPresented = true; model.searchText = args["value"] as? String ?? ""
                case "command_palette": model.showsCommandPalette = true
                case "edit_text": model.request(.editSelection)
                case "insert_link": model.insertContent(.link)
                case "insert_code": model.insertContent(.code)
                case "insert_image":
                    guard let id = model.selectedID else { throw AIError.message("请先选择主题") }
                    NodeRichContent(model: model, nodeID: id).importAttachments(imagesOnly: true)
                case "insert_file":
                    guard let id = model.selectedID else { throw AIError.message("请先选择主题") }
                    NodeRichContent(model: model, nodeID: id).importAttachments(imagesOnly: false)
                case "remove_attachment", "export_attachment":
                    guard let nodeID = model.selectedID, let node = model.document.root.find(nodeID),
                          let attachmentID = UUID(uuidString: args["value"] as? String ?? ""),
                          let attachment = node.attachments.first(where: { $0.id == attachmentID }) else { throw AIError.message("附件不存在") }
                    if action == "remove_attachment" { model.updateNode(nodeID) { $0.attachments.removeAll { $0.id == attachmentID } } }
                    else { NodeRichContent(model: model, nodeID: nodeID).exportAttachment(attachment) }
                case "import": ImportExportService.importFile(into: model)
                case "export":
                    guard let format = ExportFormat(rawValue: args["value"] as? String ?? "markdown") else { throw AIError.message("无效的导出格式") }
                    ImportExportService.export(model.document, format: format, model: model)
                case "backup": BackupStore.shared.write(model.document, force: true); result = ["status": BackupStore.shared.status]
                default: throw AIError.message("未知命令")
                }
            }
            if ["save_copy", "choose_library", "choose_backup", "open_file", "edit_text", "templates", "command_palette", "insert_link", "insert_code", "insert_image", "insert_file", "import", "export", "export_attachment"].contains(action) {
                result = ["status": "native_ui_presented_or_returned", "note": "原生操作可能等待用户或已被取消；不可据此声称导入/导出/保存已经完成，请检查实际状态或让用户确认。"]
            }
        case "mindora_library": result = try libraryAction(args)
        case "mindora_workspace": result = try workspaceAction(args)
        case "mindora_preferences": result = try preferences(args)
        default: throw AIError.message("未知工具")
        }
        if let error = library.errorMessage ?? workspace.errorMessage ?? workspace.editor?.errorMessage { throw AIError.message(error) }
        return try AIJSON.string(result)
    }
    private static func documentJSON(_ map: MindMapDocument) throws -> String {
        var copy = map
        func strip(_ node: inout MindMapNode) {
            for i in node.attachments.indices { node.attachments[i].data = Data() }
            for i in node.children.indices { strip(&node.children[i]) }
        }
        strip(&copy.nodes[0]); return String(decoding: try JSONEncoder().encode(copy), as: UTF8.self)
    }
    private static func libraryAction(_ args: [String: Any]) throws -> Any {
        let library = LibraryStore.shared, action = try text(args, "action")
        switch action {
        case "list":
            guard AIConfiguration.shared.sharesDocument else { throw AIError.message("请先启用共享导图，再读取文件名和路径") }
            var records: [[String: Any]] = []
            func visit(_ items: [LibraryItem]) { for item in items { records.append(["path": String(item.url.path.dropFirst(library.rootURL.path.count + 1)), "folder": item.isFolder]); visit(item.children) } }
            visit(library.items); return ["items": records, "scanning": library.isLoading]
        case "new_folder":
            let url = try managedURL(try text(args, "path"))
            guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path) else { throw AIError.message("父文件夹不存在") }
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false); library.reload()
        case "import": library.importMaps()
        case "recycle_list":
            guard AIConfiguration.shared.sharesDocument else { throw AIError.message("请先启用共享导图") }
            library.loadRecycleBin(); return library.recycledItems.map { ["id": $0.id.uuidString, "name": $0.record.name] }
        case "restore", "delete_permanently":
            library.loadRecycleBin()
            let id = try uuid(args, "item_id")
            guard let item = library.recycledItems.first(where: { $0.id == id }) else { throw AIError.message("回收箱项目不存在") }
            if action == "restore" { library.restoreRecycledItem(item) } else { library.permanentlyDelete(item) }
        case "empty_recycle": library.loadRecycleBin(); library.emptyRecycleBin()
        default:
            let url = try managedURL(try text(args, "path"))
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw AIError.message("不支持符号链接") }
            let item = LibraryItem(url: url, isFolder: values.isDirectory == true, children: [])
            switch action {
            case "open": if item.isFolder { library.selectFolder(url) } else { WorkspaceStore.shared.openFile(url) }
            case "rename": library.promptRename(item)
            case "move":
                if let raw = args["workspace_id"] as? String {
                    let id = try uuid(["id": raw], "id")
                    guard let space = WorkspaceCatalog.shared.workspaces.first(where: { $0.id == id }) else { throw AIError.message("空间不存在") }
                    library.moveToWorkspace(item, workspace: space)
                } else { library.moveItem(at: url, into: try managedURL(args["destination"] as? String ?? "", allowRoot: true)) }
            case "duplicate": library.duplicate(item)
            case "trash": library.moveToTrash(item)
            case "favorite": library.toggleFavorite(url)
            default: throw AIError.message("未知文件操作")
            }
        }
        return ["status": ["import", "rename"].contains(action) ? "native_dialog_returned_check_state" : "completed"]
    }
    private static func managedURL(_ path: String, allowRoot: Bool = false) throws -> URL {
        let library = LibraryStore.shared
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains(where: { $0.hasPrefix(".") }) else { throw AIError.message("仅允许工作空间内非隐藏的相对路径") }
        let url = library.rootURL.appendingPathComponent(path).standardizedFileURL
        guard library.contains(url), allowRoot || url != library.rootURL else { throw AIError.message("路径超出工作空间") }; return url
    }
    private static func workspaceAction(_ args: [String: Any]) throws -> Any {
        let catalog = WorkspaceCatalog.shared, action = try text(args, "action")
        if action == "list" { return catalog.workspaces.map { ["id": $0.id.uuidString, "name": $0.name, "introduction": $0.introduction ?? ""] } }
        if action == "create" {
            guard catalog.create(name: try text(args, "name"), iconSymbol: args["symbol"] as? String, iconText: args["icon_text"] as? String, introduction: args["introduction"] as? String, colorHex: args["color"] as? String) else { throw AIError.message(LibraryStore.shared.errorMessage ?? "未能创建工作空间") }
        } else {
            let id = try uuid(args, "id")
            guard let record = catalog.workspaces.first(where: { $0.id == id }) else { throw AIError.message("工作空间不存在") }
            switch action {
            case "switch": guard LibraryStore.shared.switchWorkspace(record) else { throw AIError.message("未能切换工作空间") }
            case "update": guard catalog.updateDetails(id, name: args["name"] as? String ?? record.name, symbol: args["symbol"] as? String ?? record.iconSymbol ?? "square.stack.3d.up.fill", iconText: args["icon_text"] as? String ?? record.iconText ?? "", introduction: args["introduction"] as? String ?? record.introduction ?? "", colorHex: args["color"] as? String ?? record.iconColorHex ?? "6264D9") else { throw AIError.message("无效的工作空间设置") }
            case "remove":
                catalog.remove(record)
                if catalog.workspaces.contains(where: { $0.id == id }) { return ["status": "cancelled_or_not_removed"] }
            default: throw AIError.message("未知工作空间操作")
            }
        }
        return ["status": "completed"]
    }
    private static func preferences(_ args: [String: Any]) throws -> Any {
        let defaults = UserDefaults.standard
        let enums = ["appearance": ["system", "light", "dark"], "defaultTheme": MapTheme.allCases.map(\.rawValue), "defaultLayout": MindMapLayout.allCases.map(\.rawValue), "backupRule": BackupRule.allCases.map(\.rawValue)]
        let bools = ["showOutlineOnOpen", "showInspectorOnOpen", "backupEnabled"]
        let ranges = ["defaultFontSize": 10.0...36.0, "backupInterval": 1.0...1440.0, "backupRetention": 1.0...500.0]
        if let raw = args["values_json"] as? String {
            let values = try AIJSON.object(Data(raw.utf8))
            for (key, value) in values {
                let valid: Bool
                if let options = enums[key] { valid = (value as? String).map(options.contains) ?? false }
                else if bools.contains(key) { valid = (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false }
                else if let range = ranges[key], let number = value as? NSNumber { valid = CFGetTypeID(number) != CFBooleanGetTypeID() && range.contains(number.doubleValue) }
                else { valid = false }
                guard valid else { throw AIError.message("不支持的设置或取值：\(key)") }
            }
            for (key, value) in values { defaults.set(value, forKey: key) }; AppPreferences.applyAppearance()
        }
        return Dictionary(uniqueKeysWithValues: (Array(enums.keys) + bools + Array(ranges.keys)).map { ($0, defaults.object(forKey: $0) ?? NSNull()) })
    }
    private static func text(_ args: [String: Any], _ key: String) throws -> String {
        guard let value = args[key] as? String, !value.isEmpty else { throw AIError.message("缺少参数 \(key)") }; return value
    }
    private static func uuid(_ args: [String: Any], _ key: String) throws -> UUID {
        guard let id = UUID(uuidString: try text(args, key)) else { throw AIError.message("无效的 UUID：\(key)") }; return id
    }
    private static func string(_ description: String) -> [String: Any] { ["type": "string", "description": description] }
    private static func tool(_ name: String, _ description: String, _ properties: [String: Any], required: [String] = []) -> [String: Any] {
        ["type": "function", "function": ["name": name, "description": description, "parameters": ["type": "object", "properties": properties, "required": required, "additionalProperties": false]]]
    }
}
