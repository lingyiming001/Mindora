# 文件与持久化

`.mindora` 为 UTF-8 JSON，UTType `app.mindora.document`，schemaVersion=1。原生 Xcode App 的 Info.plist 注册扩展名和类型；`MindoraDocument: NSDocument` 负责原生读写与自动保存；原 FileDocument 适配器保留但不承担主应用生命周期。编解码统一通过 `MapInterchange`，读入限制 20 MB，扫描嵌套深度，再解码和校验树。NSDocument 的 Data 由系统读取后交付，此限制不代表读取前已经拦截大文件 I/O。

编辑器通过同步回调更新 NSDocument 并标记修改；WorkspaceStore 在单窗口切换、返回目录、关闭和退出前提交编辑并保存，失败则保留当前内容。资料库的新建与导入使用原子写入，文件名唯一，不替换同名文档。目录管理与 security-scoped bookmark 见文件管理文档。单个已打开文档的移动使用 NSDocument 系统 API；包含打开文档的文件夹暂不允许移动。

导入：Markdown、OPML、Mindora JSON；导出：Markdown、OPML、JSON、PNG、JPEG、SVG、PDF。Markdown 大纲保留树和文字；OPML 额外保留备注；JSON 保留全部已实现领域属性。Markdown/OPML 转换会生成新的 ID，不能认为是全属性无损互转。OPML 禁用外部实体，拒绝自定义内部实体。

系统自动保存已接入文档生命周期，但保存失败、外部编辑冲突、断电和崩溃恢复尚未完成验收；没有自定义历史恢复库。未知 schema 拒绝打开写回。XMind 兼容仍需独立评估。
