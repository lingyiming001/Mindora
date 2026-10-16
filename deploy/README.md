# 本地发布包

生成当前 Mac 架构的优化版：

```sh
./scripts/package.sh
```

输出 `deploy/Mindora-arm64.zip` 或 `deploy/Mindora-x86_64.zip`。同时支持 Apple silicon 和 Intel：

```sh
./scripts/package.sh universal
```

默认启动使用 Release：`./scripts/run.sh`；开发调试可用 `./scripts/run.sh Debug`。Release 使用体积优化、全模块编译、无用代码裁剪，调试符号保留在 App 外的构建目录。包为本地 ad hoc 签名的开发预览版，正式发行仍需要开发团队签名和公证。

2026-10-15：最终 arm64 Release 构建和打包成功。应用文件总大小 5,747,173 字节，对照旧通用 Debug 版本 15,340,469 字节，减少约 62.5%；ZIP 约 2 MB。差异同时包含优化配置和架构选择，不能当作相同架构优化的独立收益。没有进行运行性能基准或 UI 验证。
