import SwiftUI

struct MindoraSettings: View {
    @State private var selection: SettingsSection = .general
    @Environment(\.openWindow) private var openWindow
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("defaultTheme") private var theme = "indigo"
    @AppStorage("defaultLayout") private var layout = "balanced"
    @AppStorage("defaultFontSize") private var fontSize = 14
    @AppStorage("showOutlineOnOpen") private var outline = true
    @AppStorage("showInspectorOnOpen") private var inspector = false
    @AppStorage("backupEnabled") private var backup = true
    @AppStorage("backupRule") private var backupRule = "interval"
    @AppStorage("backupInterval") private var interval = 5
    @AppStorage("backupRetention") private var retention = 20
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var backups = BackupStore.shared
    @ObservedObject private var workspace = WorkspaceStore.shared

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Mindora").font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("偏好设置").font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 14).padding(.top, 24).padding(.bottom, 20)
                ForEach(SettingsSection.allCases) { section in
                    Button { selection = section } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.symbol).font(.system(size: 13, weight: .medium))
                                .frame(width: 28, height: 28)
                                .background(selection == section ? Color.white.opacity(0.2) : InterfaceStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                            Text(section.title).font(.system(size: 13, weight: .medium))
                            Spacer(minLength: 0)
                        }.padding(.horizontal, 10).padding(.vertical, 6)
                            .foregroundStyle(selection == section ? Color.white : Color.primary)
                            .background(selection == section ? InterfaceStyle.accent : .clear, in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                        .accessibilityAddTraits(selection == section ? .isSelected : [])
                }
                Spacer()
                Label("本地存储 · 自由构思", systemImage: "lock.shield")
                    .font(.system(size: 10)).foregroundStyle(.secondary).padding(14)
            }.padding(.horizontal, 12).frame(width: 190).background(InterfaceStyle.panel)
            Rectangle().fill(InterfaceStyle.divider).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(selection.title).font(.system(size: 25, weight: .bold))
                    Text(selection.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                }.padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 20)
                settingsContent.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(InterfaceStyle.surface.opacity(0.6))
        }
        .frame(minWidth: 850, idealWidth: 890, minHeight: 600, idealHeight: 660)
        .tint(InterfaceStyle.accent)
    }
    @ViewBuilder private var settingsContent: some View {
                if selection == .general {
            page {
                Section("编辑器") {
                    Toggle("打开导图时显示大纲", isOn: $outline)
                    Toggle("打开导图时显示属性栏", isOn: $inspector)
                    Text("下次打开导图时生效。编辑时仍可从“显示”菜单切换。").font(.caption).foregroundStyle(.secondary)
                }
                Section("保存") {
                    Text("已提交的编辑在停止操作约 0.8 秒后自动保存到资料库；切换导图和退出前也会保存。⌘S 可立即保存，另存为只生成一份独立副本。")
                }
            }
                } else if selection == .appearance {
            page {
                Section("应用外观") {
                    Picker("外观", selection: $appearance) {
                        Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark")
                    }.pickerStyle(.segmented).onChange(of: appearance) { _, _ in AppPreferences.applyAppearance() }
                }
                Section("新建导图默认值") {
                    Picker("主题", selection: $theme) {
                        ForEach(MapTheme.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    Picker("布局", selection: $layout) {
                        ForEach(MindMapLayout.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    Stepper("主题字号：\(fontSize) pt", value: $fontSize, in: 10...33)
                    Text("中心主题大 3 pt。默认字号也用于之后添加的主题；已有主题的字号保持原样，可在属性栏单独调整。").font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("预览").font(.caption).foregroundStyle(.secondary)
                        Text("让想法自由生长").font(.system(size: CGFloat(fontSize), weight: .medium))
                            .foregroundStyle((MapTheme(rawValue: theme) ?? .indigo).color)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                        .background(InterfaceStyle.accent.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                }
            }
                } else if selection == .storage {
            page {
                Section("资料库位置") {
                    Text(library.rootURL.path).textSelection(.enabled).font(.callout)
                    HStack {
                        Button("更改位置…") { library.chooseLocation() }
                        Button("在 Finder 中显示") { library.revealInFinder(library.rootURL) }
                    }
                    Text("更改位置会保存并关闭当前导图，然后打开所选文件夹；不会搬移原有文件。外部文件打开时先复制进资料库，“另存为”只导出独立副本，不切换当前文件。").font(.caption).foregroundStyle(.secondary)
                }
                Section("回收箱") {
                    LabeledContent("文件恢复") { Button("打开回收箱", systemImage: "trash") { openWindow(id: "recycle-bin") } }
                    Text("删除的文件暂存于当前资料库中，可恢复或手动永久删除。不会自动清理。").font(.caption).foregroundStyle(.secondary)
                }
                Section("最近文件") {
                    Button("清空最近打开记录") { NSDocumentController.shared.clearRecentDocuments(nil); library.objectWillChange.send() }
                    Text("只清除菜单记录，文件仍保留在原位置。").font(.caption).foregroundStyle(.secondary)
                }
            }
                } else if selection == .backup {
            page {
                Section("自动备份") {
                    Toggle("保存导图时创建备份", isOn: $backup)
                    Picker("备份规则", selection: $backupRule) {
                        ForEach(BackupRule.allCases) { Text($0.label).tag($0.rawValue) }
                    }.disabled(!backup)
                    Text((BackupRule(rawValue: backupRule) ?? .interval).explanation)
                        .font(.caption).foregroundStyle(.secondary)
                    if backupRule == BackupRule.interval.rawValue {
                        Picker("最小备份间隔", selection: $interval) {
                            ForEach([1, 5, 15, 30, 60], id: \.self) { Text("\($0) 分钟").tag($0) }
                        }.disabled(!backup)
                    }
                    Stepper("每份导图保留 \(retention) 份", value: $retention, in: 1...100).disabled(!backup)
                    Text("自动规则由成功保存触发，不会定时唤醒应用。超额旧副本在下一次备份成功后清理。关闭备份不会删除已有副本。").font(.caption).foregroundStyle(.secondary)
                }
                Section("备份位置") {
                    Text(backups.folderURL.path).textSelection(.enabled).font(.callout)
                    HStack {
                        Button("更改位置…") { backups.chooseFolder() }
                        Button("打开备份文件夹") { backups.reveal() }
                    }
                    HStack {
                        Button("立即备份当前导图", systemImage: "arrow.clockwise") {
                            workspace.editor?.finishEditing?()
                            if let map = workspace.editor?.document { backups.write(map, force: true) }
                        }.buttonStyle(.borderedProminent).disabled(workspace.editor == nil)
                    }
                    Label(backups.status, systemImage: "clock.badge.checkmark")
                        .font(.caption).foregroundStyle(.secondary).padding(.vertical, 4)
                    Text("每份导图按独立 ID 分文件夹保存。恢复时先把备份复制到资料库并重命名，再打开；更改位置不会迁移旧备份。本机备份不能替代外部磁盘备份。").font(.caption).foregroundStyle(.secondary)
                }
            }
                } else if selection == .shortcuts {
            ShortcutHelpView().padding(.horizontal, 28).padding(.bottom, 24)
                } else {
            page {
                Section("关于 Mindora") {
                    Label("Mindora", systemImage: "point.3.connected.trianglepath.dotted").font(.largeTitle)
                    Text("让想法连接成图。")
                    LabeledContent("版本", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.2") · 开发预览")
                    Text("面向 macOS 的本地思维导图工具，用于构思、学习、写作与项目规划。")
                }
                Section("数据与隐私") {
                    Text("导图和备份保存在你选择的本机文件夹。当前版本无需账户，不提供云同步服务。")
                }
                Section("反馈") {
                    Text("反馈问题时，请附上版本、操作步骤与预期结果，并自行移除导图中的私人内容。当前为开发预览版。")
                }
            }
                }
    }
    private func page<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Form { content() }.formStyle(.grouped).scrollContentBackground(.hidden).padding(.horizontal, 12).padding(.bottom, 12)
    }
}


private enum SettingsSection: String, CaseIterable, Identifiable {
    case general, appearance, storage, backup, shortcuts, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "常规"
        case .appearance: "主题与字体"
        case .storage: "文件存储"
        case .backup: "备份"
        case .shortcuts: "快捷键"
        case .about: "关于 Mindora"
        }
    }
    var symbol: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .appearance: "paintpalette"
        case .storage: "folder"
        case .backup: "clock.arrow.circlepath"
        case .shortcuts: "keyboard"
        case .about: "info.circle"
        }
    }
    var subtitle: String {
        switch self {
        case .general: "按你的习惯，安排每一次构思。"
        case .appearance: "选择舒适的外观与清晰的表达方式。"
        case .storage: "掌握文件的位置，让每一个想法都有归处。"
        case .backup: "为重要的内容，保留可追溯的副本。"
        case .shortcuts: "减少打断，让思路跟上你的节奏。"
        case .about: "让想法连接成图。"
        }
    }
}

struct ShortcutHelpView: View {
    private let groups: [(String, [(String, String)])] = [
        ("文件与应用", [("新建导图", "⌘N"), ("新建文件夹", "⇧⌘N"), ("打开 / 保存 / 另存为", "⌘O / ⌘S / ⇧⌘S"), ("返回资料库", "⌘["), ("设置", "⌘,"), ("快捷键帮助", "⌘/")]),
        ("主题编辑 · 画布获得焦点时", [("添加子主题 / 同级主题", "⌘K / ⇧⌘K"), ("添加子主题（画布）", "Tab"), ("插入网址 / 代码", "⌥⌘K / ⌥⌘C"), ("编辑选中文字", "⌘E / F2"), ("文字内换行", "⇧Return"), ("删除选中主题", "Delete"), ("切换选中主题 / 扩展选择", "方向键 / ⇧方向键"), ("选中中心主题", "Esc"), ("全选 / 复制 / 剪切 / 粘贴", "⌘A / ⌘C / ⌘X / ⌘V"), ("创建主题副本", "⌘D"), ("展开或折叠", "⌘."), ("同级主题上移 / 下移", "⌥⌘↑ / ⌥⌘↓"), ("撤销 / 重做", "⌘Z / ⇧⌘Z")]),
        ("导航与视图", [("搜索", "⌘F"), ("命令面板", "⇧⌘P"), ("适应画布 / 定位选中主题", "⌘0 / ⌘L"), ("显示或隐藏大纲 / 属性", "⌥⌘1 / ⌥⌘2"), ("专注模式", "⇧⌘F"), ("导入", "⇧⌘I"), ("缩放画布", "触控板捏合 / ⌘滚动")])
    ]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("键盘快捷键").font(.title2.bold())
                Text("Tab、Delete 和方向键在画布中操作主题；Return 不再创建主题，仅用于文字编辑确认。Mac 功能键设置可能需要按住 fn 使用 F2。")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(groups.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(groups[index].0).font(.headline)
                        ForEach(groups[index].1.indices, id: \.self) { row in
                            HStack {
                                Text(groups[index].1[row].0)
                                Spacer(minLength: 20)
                                Text(groups[index].1[row].1).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Divider()
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
