# 项目目录结构

```text
Mindora/
├── Mindora.xcodeproj/                  # 原生 App 工程与共享 Scheme
├── Package.swift                      # 命令行开发与单元测试
├── Sources/Mindora/
│   ├── App/                           # 启动、单窗口工作台、资料库首页、编辑器组合、菜单快捷键
│   ├── Domain/                        # 文档树、样式、属性与数据校验
│   ├── Editor/                        # 可逆命令、历史、选择与操作用例
│   ├── Layout/                        # 动态文字测量及四种布局
│   ├── Canvas/                        # AppKit 画布、视口、命中、绘制、文本编辑
│   ├── DesignSystem/                  # 主题色板、深浅色、节点颜色继承
│   ├── Features/                      # 文件资料库、目录树、属性、模板、命令面板
│   ├── ImportExport/                  # Markdown/OPML/JSON 与图像/矢量导出
│   └── Persistence/                   # NSDocument 原生读写及 FileDocument 兼容适配
├── Resources/
│   ├── Info.plist                     # App 元数据与文档 UTI
│   ├── Mindora.entitlements            # 正式签名的沙盒与文件权限
│   └── AppIcon.icns                    # 应用图标
├── scripts/                           # 工程生成、图标生成、构建与启动
├── Tests/MindoraTests/                 # SwiftPM 单元和文件格式测试
└── docs/                              # 设计与开发续航
```

View 与 Feature 的状态放 `Features`/`App`；核心编辑状态放 `EditorModel`。文档 Model 在 `Domain`，纯树操作在 `NodeTree`。文件管理的系统集成集中于 `LibraryStore`，不让每个目录行直接执行磁盘操作。画布交互由 NSView 实现，主题 Token 与布局几何不嵌入文件管理层。

工程仍为单 App target，测试通过 SwiftPM 运行。生成器 `scripts/generate_project.py` 读取真实源码目录，产生稳定 ID；添加源码后重新运行。不要手动编辑生成的 `project.pbxproj`，修改生成器设置后重新生成。
