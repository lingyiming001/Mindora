# 单窗口资料库与编辑工作台

更新：2026-10-13。按用户要求，不运行测试或界面验证，本次也未构建新版本。

## 用户流程

正常启动直接显示资料库，左侧为目录导航，右侧为当前文件夹的文件夹/导图卡片。启动不弹系统打开文件窗口，也不自动生成空白导图。

⌘N 或“新建导图”在当前文件夹中创建 `.mindora` 文件，并将当前工作台内容切到编辑器。点击已有导图、⌘O、“打开最近”以及 Finder 打开文件均路由到同一个工作台。点击文件夹会保存当前导图并显示该文件夹内容。编辑器左上角“返回资料库”或 ⌘[ 保存后返回目录。

切换文件时先读取并校验目标，再提交当前原生文字编辑并保存当前文件；失败则保留当前编辑器并显示错误。创建新文件前也先保存当前编辑。不同文件拥有独立 EditorModel，切换时重建画布和选择状态。

## 架构

```mermaid
flowchart LR
 App["单个 SwiftUI Window"] --> Workspace["WorkspaceStore"]
 Workspace --> Folder["资料库文件夹视图"]
 Workspace --> Editor["当前 EditorModel"]
 Workspace --> Doc["MindoraDocument / NSDocument"]
 Library["LibraryStore 文件操作"] --> Workspace
 Editor --> Doc
 Doc --> File["版本化 JSON 文件"]
```

`MindoraApp` 使用具名 `Window` 作为唯一主窗口；`WorkspaceView` 根据是否存在活动编辑器显示资料库或编辑器；`WorkspaceStore` 管切换、保存、权限生命周期和窗口标题。`MindoraDocument` 使用 NSDocument 系统协调写入和自动保存，但不创建文档窗口。

原 `MindoraFile: FileDocument` 留作编解码兼容适配，已不用于应用启动。Info.plist 指定 MindoraDocument 为原生文档类，使系统文件入口也能进入工作台。

## 数据与关闭

编辑命令同步更新 NSDocument 内容并标记修改；切换前调用协调写入并清除编辑状态。打开的外部文件在会话期间保持 security-scoped resource 访问，切换/关闭后释放。另存为成功后才更新活动文件地址。

主窗口关闭和应用退出前提交当前文字编辑并保存；保存失败阻止关闭/退出并显示原因。资料库仍提供目录扫描、收藏、最近打开、移动和废纸篓等功能。崩溃恢复、外部编辑冲突、完整沙盒运行仍待后续验收。
