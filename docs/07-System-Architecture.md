# 系统架构

架构采用轻量 MVVM + 单向编辑命令流。文档领域模型不依赖 UI；编辑器持有瞬时选择与 viewport；布局只消费不可变文档快照；持久化负责校验和编解码。工程为单 App target，SwiftPM 保留开发入口。当前改为单窗口工作台，WorkspaceStore 协调资料库与编辑器切换，详见 docs/20-Single-Window-Workspace.md。

## 总体与依赖

```mermaid
flowchart LR
 App["App 生命周期"] --> UI["SwiftUI 窗口"]
 UI --> Editor["EditorModel / Commands"]
 Editor --> Domain["Domain 文档"]
 Editor --> Layout["LayoutEngine"]
 UI --> Canvas["Canvas Rendering"]
 Layout --> Domain
 Canvas --> Layout
 App --> Workspace["WorkspaceStore"]
 Workspace --> File["MindoraDocument / NSDocument"]
 File --> Domain
```
UI 不能直接改树；正式命令系统记录逆操作或文档快照。Canvas 只读布局结果。文件层不依赖布局或 UI。

```mermaid
flowchart TD
 Features --> Editor
 Features --> DesignSystem
 Editor --> Domain
 Editor --> LayoutEngine
 LayoutEngine --> Domain
 Rendering --> LayoutEngine
 Persistence --> Domain
 Infrastructure --> Domain
```
依赖箭头指向被依赖模块。未来 AI 和同步通过领域用例接口进入，不能直接修改视图状态。

## 画布与布局

```mermaid
flowchart LR
 Document --> Measure["节点测量"] --> Layout["布局求解"] --> Spatial["空间索引"]
 Layout --> Edges["连线几何"]
 Spatial --> Cull["视口裁剪"] --> Draw["Core Graphics / SwiftUI Canvas"]
 Edges --> Draw
 Viewport --> Cull
 Viewport --> Hit["命中检测"]
 Spatial --> Hit
```
当前实现动态节点尺寸与全量布局、可视区域绘制裁剪；空间索引和增量布局尚未实现。布局结果不序列化。

```mermaid
flowchart TD
 Input["文档树和布局类型"] --> Assign["分配根分支方向"]
 Assign --> Weight["后序计算子树高度"]
 Weight --> Place["前序放置节点"]
 Place --> Connect["生成连接线端点"]
 Connect --> Bounds["计算内容边界"]
```
当前左右平衡按根子树跨度权重分边，降低视觉偏差。

## 数据流与时序

```mermaid
flowchart LR
 User --> Intent["编辑意图"] --> Command["校验并执行命令"] --> Document
 Document --> Revision["修订号"] --> Layout
 Layout --> View["画布与属性区"]
 Document --> Autosave["系统自动保存"]
```

```mermaid
sequenceDiagram
 participant U as 用户
 participant V as 视图
 participant E as EditorModel
 participant L as LayoutEngine
 participant F as MindoraDocument
 U->>V: Tab 添加子节点
 V->>E: addChild(parentID)
 E->>E: 校验、存撤销快照、更新树
 E->>L: 计算布局
 L-->>V: frames + edges
 E-->>F: 文档变更
 F-->>U: 标题栏保存状态
```
EditorModel 当前同步计算布局；节点规模增大时转到可取消后台任务。

```mermaid
sequenceDiagram
 participant E as EditorModel
 participant F as MindoraDocument
 participant OS as 文档系统
 participant Disk as 磁盘
 E->>F: 发布文档快照
 OS->>F: 请求 fileWrapper
 F->>F: 校验与 JSON 编码
 F-->>OS: FileWrapper
 OS->>Disk: 协调写入与替换
 Disk-->>OS: 完成或错误
 OS-->>E: 更新保存状态
```
系统文档协调写入需在正式 App 工程中做故障注入验证。

## ER 模型

```mermaid
erDiagram
 MIND_MAP_DOCUMENT ||--|| MIND_MAP_NODE : root
 MIND_MAP_NODE ||--o{ MIND_MAP_NODE : children
 MIND_MAP_DOCUMENT ||--|| MIND_MAP_LAYOUT : uses
 MIND_MAP_NODE ||--o| NODE_STYLE : overrides
 MIND_MAP_NODE ||--o{ NODE_ATTACHMENT : has_future
 MIND_MAP_DOCUMENT ||--o{ MIND_MAP_EDGE : relates_future
```
当前文件只序列化树、布局和可选节点样式；附件、关系边是预留概念。
