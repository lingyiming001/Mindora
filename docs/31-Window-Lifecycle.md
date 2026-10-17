# 主窗口关闭与面板任务

主窗口经 `windowShouldClose` 保存成功后，在 `windowWillClose` 统一清理：

- 取消自动保存、资料库扫描、文件监听及已登记的预览任务。
- 关闭其他可见或最小化窗口（设置、回收箱、快捷键、颜色面板等），取消模态会话并结束附属 sheet。
- 清空模板、命令面板、内容插入和工作空间编辑面板状态，释放当前文档。
- 保存失败时拒绝关闭，保留编辑器和辅助窗口。

再次打开主窗口时恢复任务登记、目录监听和扫描。关闭后新登记的任务立即取消，避免 SwiftUI 刷新重新启动请求。扫描及预览在取消后不再发布结果；同步解码/布局仅在检查点退出，不保证中断正在执行的同步函数。

`PanelActivityStore.register(task)` 用于登记窗口关联任务，结束时调用 `finish(id)`；关闭时统一 `cancelAll()`。AI 助手及 MCP 连接测试已登记于此；关闭会取消 URLSession 请求和 stdio 子进程，并向 HTTP MCP 尽力发送取消通知。AI 窗口和测试面板还监听实际 AppKit 窗口关闭事件，避免 SwiftUI 保留视图时漏掉取消。详见 docs/32-AI-and-MCP.md。

初次实现仅源码检查；随后随 AI 功能通过 Debug/Release 构建，最终结果见 .agents/STATUS.md。未运行测试或界面验证。
