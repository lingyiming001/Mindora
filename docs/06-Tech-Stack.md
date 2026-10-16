# 技术栈选型

最低 macOS 14；Swift 5.10 语言模式（可随 Xcode 升级到 Swift 6 严格并发）。SwiftUI 管窗口、工具栏、文件导航与属性面板；当前画布已经封装为 AppKit `NSView`，用 Core Graphics/AppKit 绘制并使用 NSTextView 原生编辑。Metal 仅在实测证明 CPU 渲染不达标后采用，避免初期维护负担。

| 技术 | 位置与原因 | 风险/替代 |
| --- | --- | --- |
| SwiftUI | 单个工作台窗口与侧栏开发快 | 节点渲染由 AppKit 画布承担 |
| Core Graphics/Core Animation | 路径、文字、裁剪和图层 | 需管理坐标与失效区；当前已用于画布 |
| NSDocument + UTType | 系统读写/自动保存；工作台统一显示文档 | 文档不拥有独立窗口，切换与关闭需由 WorkspaceStore 协调 |
| JSON + Codable | 可读、易迁移、无外部依赖 | 10k 节点全量写入慢；未来包格式/SQLite 索引 |
| Swift Concurrency | 后台布局与导入导出 | UI 主线程隔离与过期结果管理 |
| XCTest | 稳定广泛支持 | Swift Testing 可用于新测试 |

SwiftData/Core Data 不承担导图主文件，因为用户需要可移动、可备份的独立文档。SQLite 只考虑 V1 的最近文件索引和搜索缓存；缓存可重建。Combine 不额外引入。所有技术选择以 Instruments 实测为准。
