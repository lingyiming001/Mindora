# 性能优化

目标为 Apple Silicon 中档 Mac、Release 构建、标准 1100×720 pt 窗口，数据由固定种子的宽树和深树各半组成。以下为门槛，不是当前实测。

| 节点 | 打开 p95 | 全量布局 p95 | 平移/缩放 | 额外内存 |
| --- | --- | --- | --- | --- |
| 100 | < 0.5 s | < 16 ms | 60 fps | < 80 MB |
| 1,000 | < 1.5 s | < 80 ms | 60 fps | < 180 MB |
| 5,000 | < 4 s | < 300 ms | ≥ 45 fps | < 450 MB |
| 10,000 | < 8 s | < 700 ms | ≥ 30 fps | < 800 MB |

冷启动目标 < 1.5 s；节点编辑反馈 p95 < 100 ms；1,000 节点保存 p95 < 1 s。测量用 Instruments Time Profiler、Core Animation、Allocations、System Trace 和 os_signpost；至少 10 次暖机后 30 次采样，报告设备、系统、构建和 p50/p95。优化顺序为避免整树视图更新、可视裁剪、缓存文本测量、增量布局、可逆命令、必要时 AppKit Core Graphics。自动保存可靠性用注入写入失败与外部冲突验证，不以平均性能代替数据安全。
