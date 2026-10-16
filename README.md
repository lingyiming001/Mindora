# Mindora

本地优先的 macOS 原生思维导图应用，部署目标 macOS 14。当前为开发预览版。

## 启动

用 Xcode 打开 `Mindora.xcodeproj`，选择 `Mindora` scheme 运行。启动直接显示资料库和文件夹内容；新建或打开导图在当前窗口进入编辑器，左上角“返回资料库”可回到文件夹。

也可在项目根目录运行：

```sh
./scripts/run.sh
```

如果旧版应用仍在运行，先用 ⌘Q 退出，再运行脚本，以加载新代码。脚本会生成工程文件、构建本地 App、进行 ad hoc 签名并启动。生成物位于 `.build/xcode/Build/Products/Debug/Mindora.app`。本地脚本没有附加发行沙盒 entitlement；正式签名和沙盒运行需在 Xcode 选择开发团队后完成。`Package.swift` 保留作为命令行开发与单元测试入口。

## 编辑功能

- 多级主题、新增子/同级主题、双击或 ⌘E 就地编辑，Shift+Return 换行。
- 多选、复制/剪切/粘贴、分支副本、批量删除、拖拽跨分支移动、同级排序。
- 可逆编辑命令、撤销/重做、文字输入合并为编辑事务。
- 左右平衡、向右树形、向左树形、组织结构四种布局；动态文字测量。
- 原生 AppKit 画布、指针锚点缩放、平移、适应窗口、可视范围裁剪。
- 大纲、主题/备注/标签搜索、命令面板、专注模式。
- 备注、标签、优先级、进度、节点颜色/字号和四套主题；系统深浅色外观。
- 十个模板（含系统设计、API 设计、Bug 排查、代码评审、发布检查），Markdown/OPML/JSON 导入，Markdown/OPML/JSON/PNG/JPEG/SVG/PDF 导出。

## 文件与目录管理

左侧有“文件 / 大纲”切换和新建入口。

- **⌘N**：在当前文件夹中新建并打开思维导图。
- **⇧⌘N**：在当前文件夹中新建文件夹。
- **⌘O / ⌘S / ⇧⌘S**：打开、保存、另存为。
- 目录树、搜索、收藏、最近打开、导入已有导图。
- 右键重命名、创建副本、移动、在 Finder 中显示、移到废纸篓。
- 拖动资料库里的文件或文件夹到目标文件夹上移动。
- 可选择资料库位置，使用 security-scoped bookmark 记住授权。默认位置是应用支持目录中的 `Mindora/Library`。

更多说明见 [文件管理](docs/18-File-Library.md)、[快捷键](docs/19-Keyboard-Shortcuts.md) 与 [单窗口工作台](docs/20-Single-Window-Workspace.md)。

## 开发与实现状态

目录按 `App / Domain / Editor / Layout / Canvas / DesignSystem / Features / ImportExport / Persistence` 划分，工程由 `scripts/generate_project.py` 根据源码树生成。新增 Swift 文件后运行该脚本，或直接运行启动脚本。

历史上 19 项测试通过，覆盖命令撤销、文件格式、布局与导出；资料库版本已完成启动构建。单窗口版本已完成启动构建。**2026-10-14 的最新界面改动按用户要求未构建或测试**，需要用户运行确认。尚待完成的功能包括关系线/概要/附件、高级布局、历史恢复、性能基准、AI 与同步，见 [开发状态](docs/dev/STATUS.md)。

## 界面布局

资料库区分文件夹与导图，支持内容缩略图及网格/列表视图。编辑器默认显示大纲，属性栏按需打开并分为内容、样式、任务。详细说明与参考来源见 [界面整理](docs/21-Interface-Refinement.md)。

## 设计文档

[产品概览](docs/01-Product-Overview.md) · [PRD](docs/02-PRD.md) · [技术栈](docs/06-Tech-Stack.md) · [架构](docs/07-System-Architecture.md) · [目录结构](docs/08-Project-Structure.md) · [开发路线](docs/16-Development-Roadmap.md)。Notion 保存设计快照，仓库源码与开发状态记录是当前实现的事实来源。

## 设置与快捷键帮助

使用 `⌘,` 打开六页设置，配置外观、新建导图主题/布局/字号、默认面板、资料库位置和保存后备份；`⌘/` 打开快捷键帮助。详见 [设置与备份](docs/22-Settings-and-Backups.md)。本轮实现未构建、未测试，需重新运行启动脚本后自行验证。

开发者模板也提供独立文件，见 [模板使用说明](Templates/Developer/README.md)。

## 回收箱

在资料库侧栏或“设置 → 文件存储”打开回收箱，支持恢复、永久删除与清空。删除文件保存在当前资料库隐藏目录中，不会自动清理。详见 [回收箱与设置布局](docs/24-Recycle-Bin-and-Settings.md)。本轮实现未构建或测试。

## 优化版与打包

`./scripts/run.sh` 默认构建启动 Release，本机架构；调试用 `./scripts/run.sh Debug`。`./scripts/package.sh` 生成本机架构压缩包，通用包使用 `./scripts/package.sh universal`。体积数据及验证边界见 [性能与体积](docs/28-Performance-and-Size.md)。
