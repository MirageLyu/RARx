# RARx

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-black.svg)](#构建)

[github.com/MirageLyu/RARx](https://github.com/MirageLyu/RARx)

一个面向 macOS 的轻量、后台式 RAR 解压器。它把解压交互做成接近系统归档工具的方式：

> **在 Finder 中双击 `.rar` → 直接解压到压缩包所在文件夹 → 不打开主窗口、不询问目标位置，完成后退出。**

安装后，RARx 会注册为当前用户的默认 `.rar` 打开方式，安装位置为 `/Applications/RARx.app`。

## 交互

- 默认完全静默：不显示主窗口、Dock 弹窗或完成对话框。
- 加密压缩包只在需要时显示一个浮动密码框；输入密码后继续在后台解压。
- 损坏、缺卷、权限不足等异常才显示浮动错误提示。
- 同名文件**永不覆盖**：自动保留两者，追加 ` 2`、` 3` 等后缀。
- 双击分卷的 `part2.rar` 会自动从 `part1.rar` 开始解压。
- 多个 `.rar` 同时打开会按顺序排队处理。
- 可选“解压进度小窗”（默认关闭）：解压超过 1 秒时在屏幕右下角显示非激活式进度条和取消按钮，不抢焦点。
- 手动打开 RARx 才会显示设置窗口；正常 Finder 解压不会出现。

## 功能与质量

- 内置 **UnRAR 7.13**（universal：arm64 + x86_64），支持 RAR4 / RAR5、加密头、加密文件、分卷、Unicode 文件名和符号链接。
- 原生 Swift/AppKit + SwiftUI 设置界面，无 Electron/浏览器运行时。
- 使用隐藏 staging 目录解压，全部成功后才合并到目标目录；失败或取消不会留下半成品或覆盖原文件。
- 子进程通过 `/usr/bin/sandbox-exec` 限制为只能写 staging 目录，配合路径规范化、越界符号链接检查和硬链接拒绝。
- 密码通过进程 stdin 传给 `unrar`，不出现在命令行参数、日志或网络请求中。
- 崩溃遗留的 staging 目录带有 PID 锁，后续解压会自动识别并清理。
- 磁盘空间预检；写入失败会回滚已合并的文件。
- 全量诊断日志（不含密码）：`~/Library/Logs/RARx/RARx.log`。
- 自适应深色/浅色外观，自带应用图标和 `.rar` 文档图标。
- 程序化核心断言 + Finder 路径端到端测试；安装脚本显式注册并验证 LaunchServices 默认处理器。

## 安装

```bash
git clone https://github.com/MirageLyu/RARx.git
cd RARx
./scripts/install.sh
```

安装脚本会：

1. 检查/构建 `build/RARx.app`；
2. 停止正在运行的 RARx；
3. 安装到 `/Applications/RARx.app`；
4. 刷新 LaunchServices，注销 `build/` 下的开发副本；
5. 设置 `com.rarlab.rar-archive` 的默认处理器并验证。

安装完成后直接在 Finder 双击任意 `.rar` 即可。

## 构建

要求 macOS 13+ 和 Command Line Tools（`swiftc`、`lipo`、`iconutil`）。

```bash
./scripts/build-engine.sh   # 可选：没有 build/engine/unrar 时自动执行
./scripts/build-app.sh
```

产物：

- `build/RARx.app` — 已启用 hardened runtime 的 ad-hoc 签名通用 App；
- `build/engine/unrar` — 从 `vendor/unrar` 源码构建的 universal UnRAR；
- `build/icons/` — 生成的 `.icns` 资源。

## 测试

```bash
./scripts/test.sh
# 已安装版本（包含默认打开方式测试）：
APP=/Applications/RARx.app ./scripts/test.sh
```

测试覆盖：正常解压、Unicode/空格路径、空目录、同名冲突、嵌套合并、加密头、加密文件、错误密码、分卷从 part2 进入、缺卷、损坏/截断包、不安全符号链接、硬链接、staging 清理、密码不落日志，以及 Finder 双击、批量打开和默认处理器。

`Tests/Fixtures` 中的 RAR 样本仅用于测试，不会进入 App bundle。

## 安全设计

1. **不覆盖**：staging 成功后才合并；冲突项重命名，不使用 `FileManager.replaceItem`。
2. **写隔离**：解压子进程由 sandbox 限制只能写 staging，即使归档构造了 `../` 或符号链接穿越也无法写出目标目录。
3. **链接校验**：提交前移除指向 staging 外部的符号链接和硬链接项目。
4. **密码隔离**：`-p` + stdin，避免 `ps` 泄露；日志明确不记录密码和 stdin。
5. **失败清理**：取消/错误自动删除 staging；进程崩溃则通过 PID 锁在下次运行清理。
6. **回滚**：合并中途失败时按操作日志逐项回滚。
7. **无 shell**：所有子进程使用 `Process` 参数数组，不经过 shell 拼接。

## 目录

```text
Sources/Core/     引擎封装、进程运行、进度、staging、合并、安全检查
Sources/App/      Finder 事件、后台任务、密码/错误提示、HUD、设置
Resources/        Info.plist、第三方许可
scripts/          构建、图标、安装、测试
Tests/            核心测试与 RAR fixtures
vendor/unrar/     UnRAR 源码（官方 freeware 许可）
```

## 日志与诊断

- 日志：`~/Library/Logs/RARx/RARx.log`（超过 2 MB 自动轮转）
- 设置窗口 → “打开日志”
- 错误提示 → “查看日志”

## 卸载

```bash
pkill -x RARx 2>/dev/null || true
rm -rf /Applications/RARx.app
```

卸载后 macOS 可能仍保留“默认打开方式”记录；重新安装或对任意 `.rar` 使用“打开方式 → 其他”选择其他应用即可覆盖。

## 已知限制

- **不创建 RAR**：RARx 只解压。UnRAR 许可证禁止用其源码开发 RAR 兼容压缩器。
- **签名与分发**：当前为 ad-hoc 签名（已启用 hardened runtime），适合本机/内部分发；面向公网分发还需 Developer ID Application 签名、notarization，并替换 `scripts/build-app.sh` 中的签名步骤。
- **Intel 兼容性**：App 与引擎均包含 x86_64 slice，但本机为 Apple Silicon，未在 Intel Mac 或 Rosetta 下做运行时验证。
- **同名策略固定为“保留两者”**，暂未提供静默覆盖选项。
- **首次访问受保护目录**：从桌面/文稿/下载解压时，macOS 可能弹出一次文件夹访问授权（TCC），这是系统行为。
- **密码框聚焦**：macOS 14+ 的协作式激活机制可能不会让后台 App 主动抢焦点；密码框会浮到最前，点一下即可输入。
- **UnRAR 上游**：解压能力由内置 UnRAR 版本决定，不支持未来新增的压缩/加密算法扩展。

## License

RARx 的原创代码以 **MIT License** 发布，详见 [`LICENSE`](LICENSE)。

UnRAR 是独立的 freeware 组件，**不适用 MIT License**。其完整许可和版权声明见 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)，安装后位于 `RARx.app/Contents/Resources/THIRD_PARTY_NOTICES.txt`，也可从设置窗口的“RARx 许可”和“第三方许可”查看。

RAR 是 RARLAB 的商标。RARx 与 RARLAB 无关联。
