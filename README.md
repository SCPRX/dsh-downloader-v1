# 落锤

原生界面的本机 DSH 客户端（Android）。内置 Linux 运行环境，APK 自带 198MB 运行时，首次打开解压后即可离线使用引擎。

## 目录

- `main.dart` — Flutter 界面（聊天 / 会话 / 设置 / 星空背景 / 终端 / 文件）
- `MainActivity.kt` — 原生层：proot 启动、环境解压、JSON-RPC 桥、通知保活、图片选择、TTS、系统设置跳转
- `icons/` — 图标源文件（构建时复制到 Android 资源）
- `patches/` — 引擎补丁（会话日志硬链接 → rename、附件复制），运行时由 App 下载并替换
- `android/` — Android 工程（Gradle 内联打包运行时，免工作流改动）

## 构建

推送 `main` 自动触发 GitHub Actions 构建，产物为 `Final-APK`（约 200MB）。首次解包较慢，属正常。

## 版本规则

版本全部由 CI 构建次数推导：

- 版本名 = `2.<次数÷100 % 100>.<次数%100>`
- 构建号 = 次数
- 主版本每 10000 次构建 +1

## 说明

- 聊天走 SDK stdio JSON-RPC；网页模式启动本地 `dsh web`。
- 停止生成通过结束引擎进程 + `session/resume` 恢复会话实现（协议无 cancel）。
- 不收集任何数据；API Key 只存本机。
