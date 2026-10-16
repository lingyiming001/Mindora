# 核心数据模型

v1 文档：`MindMapDocument(schemaVersion,id,title,layout,theme,nodes)`；`nodes` 必须恰有一个根节点。节点：`MindMapNode(id,title,children,isCollapsed,note,style,tags,priority,progress)`。父子关系由嵌套树表达，同级顺序就是 children 数组顺序，UUID 全文档唯一。新增字段通过自定义 Codable 解码提供默认值，保持早期 v1 文件可读。

`NodeStyle` 包含可选 colorHex 与 fontSize；theme 是 indigo/forest/sunset/graphite，节点颜色覆盖后由后代继承。priority 为 0–3（0 未设置），progress 为 nil 或 0–100。字体范围 10–36 pt，颜色为六位十六进制。节点数最多 10,000，深度最多 128；文字最多 10,000 字符，备注最多 100,000 字符。JSON 在解码前限制 20 MB 和嵌套深度。

`NodeProperties` 是节点可编辑属性快照，排除 children 与 id；更新属性的撤销记录不保存整份文档。`NodeLocation(parentID,index)` 标记插入、删除和移动位置。`EditCommand` 含 update/insert/remove/move/layout/theme/batch/replace，每项有逆命令；批量命令按逆序撤销。模板/整份导入用 replace，保留修改前后文档以便恢复。

`EditorModel` 持有选择集合、焦点 ID、视口、大纲/侧栏状态、搜索和历史；撤销后重新约束选择到可见节点。连续属性文字编辑按节点与字段在 0.8 秒窗口内合并。`CanvasViewport` 和 `LayoutResult` 不写入主文件，后者包含矩形、树边、可见节点和内容边界。

关系线、附件、边界、概要仍为未来模型，当前 v1 文件没有这些对象。未来 schema 迁移按逐版本纯函数实现；新版本未知 schema 拒绝写回。
