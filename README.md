# AstraBar

**把实际可见的 AI 额度放在 Mac 顶部菜单栏。** Swift 原生应用，无第三方运行时依赖，无遥测。

菜单栏示例：`Codex 66%`。只有接口明确返回 Astra 配额时才显示 `Astra 66%`。这里是**剩余额度百分比，不是聊天条数**。

> **AstraBar 不能读取服务端未公开的 Astra 独立额度，也不能提供 ChatGPT 网页每周还剩多少次对话。** 官方只返回 Codex 总额度时，应用如实显示 Codex，并提示 Astra 专属额度未返回。不把 reserve / Spark / 总额度改名成 Astra。

## 安装

需要 macOS 13+，以及已登录 ChatGPT 订阅账号的 Codex CLI 或包含可执行程序的 Codex 桌面应用。

1. 在 [Releases](https://github.com/lixiangwelding/astra-bar/releases/latest) 下载 `AstraBar-<版本>-macOS-universal.zip` 并解压。
2. 将 `AstraBar.app` 放入“应用程序”，双击启动。它只出现在顶部菜单栏，不占 Dock。
3. 点开查看返回的周额度、其他周期额度、套餐标识、数据时间和重置时间。默认每 60 秒自动刷新。
4. 找不到 Codex 时，在齿轮菜单选择 **选择 Codex 程序**，选择真正的 `codex` 可执行文件。终端 `command -v codex` 可查看路径，不要选择 `.app` 文件夹。

登录启动是可选项：安装后在齿轮菜单打开“登录时启动”。不会在首次运行时自动开启。卸载前取消该选项，退出并删除应用。

### 首次打开与签名

当前安装包使用 **ad-hoc 本机签名，不是 Apple Developer ID 签名，也没有公证**。系统可能拦截首次打开。确认仓库来源并核验 SHA-256 后，在“系统设置 → 隐私与安全性”中按提示允许这一个应用。不要关闭全局 Gatekeeper。校验和只能检测下载损坏，不能替代开发者身份认证。有开发环境时也可自行编译。

## 数据来源与准确性

默认使用 OpenAI 官方文档公开的只读方法：启动本机 `codex app-server`，握手后只调用 `account/rateLimits/read`。本应用不启动模型任务、不创建对话、不调用 MCP 工具、不使用重置券。认证由 Codex 管理，本应用不直接读取或保存 `auth.json`、Cookie 或 access token。

日志模式需要从齿轮菜单**主动选择**。读取 `CODEX_HOME/sessions` 或 `~/.codex/sessions`，也可自选目录。只提取 `event_msg → token_count → rate_limits` 元数据，不上传或持久保存会话正文；此模式不发起网络请求。

- 日志是历史快照，可能来自其他账号，菜单栏用 `~` 标识。实时接口出错不会静默切换日志。
- 窗口长度为 `10080` 分钟才叫每周，不假定 primary 是周额度。其余周期按实际长度显示。
- 观测超过 10 分钟、时间异常、查询失败或已过重置时间，菜单栏显示 `—`；弹窗旧数字标为历史记录。
- 重置到点不自行补成 100%，必须等新的真实结果。
- 最多检查 20,000 个目录条目、近期 24 个 JSONL、每个文件尾部 512 KiB，并标注有界扫描。
- 套餐标识来自服务器。不会把 `pro` 擅自换算成 Pro 20x，不根据 token 或百分比估算对话次数。
- 时间使用 macOS 本地时区；所有配额分别展示。

## 构建

Swift 5.9+。构建应用可用 Apple Command Line Tools；运行 XCTest 单元测试需要**完整 Xcode**。GitHub CI 使用完整 Xcode 环境。应用本身不依赖 Python、Node、Electron。

```sh
swift build
swift test                 # macOS 需要完整 Xcode
bash scripts/package.sh   # macOS Universal：Apple Silicon + Intel
open dist/AstraBar.app
```

只构建本机架构：`ARCH=native bash scripts/package.sh`。

命令行查看器共用同一解析核心：

```sh
swift run astra-usage
swift run astra-usage --json
swift run astra-usage --logs --sessions "$HOME/.codex/sessions"
swift run astra-usage --codex /absolute/path/to/codex
```

Linux 可以编译测试核心和 CLI，不能生成或运行 macOS 界面。

## 验证与发布

包含 35 项合成回归测试：周/短周期识别、多配额隔离、缺失字段、非法数值、过期状态、日志尾部/符号链接、只读 RPC 握手、超时、EOF 和错误脱敏。真实账号结果、截图、日志不得入库。

`--smoke --capture /private/path/menu.png` 会启动真实菜单栏，采集本应用视图并退出，不截取整个桌面。截图路径应放在忽略的 `private-evidence/` 中。

见 [架构](docs/ARCHITECTURE.md)、[发布说明](docs/RELEASE.md)、[安全说明](SECURITY.md)。安装包未公证，Intel 版本可交叉编译，但 Intel 实机兼容性需要额外验证。

## 技术依据与其他项目

- [OpenAI App Server 官方文档](https://developers.openai.com/codex/app-server)：握手与 account/rateLimits/read。
- [OpenAI Codex](https://github.com/openai/codex)：客户端实现。
- [Astra 配额可见性 issue](https://github.com/openai/codex/issues/43006)：用户反馈，不是对所有账号的官方保证。
- [CodexBar](https://github.com/steipete/CodexBar)：覆盖更多提供商的菜单栏项目。本项目为独立轻量实现，未复制其源码。

本项目不是 OpenAI 官方产品，与 OpenAI 无隶属关系。MIT License。
