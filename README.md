# codex-state

Codex State 是一个原生 macOS 监控ChatGPT用量工具。模拟IPhone灵动岛效果，悬停查看剩余周额度和今日统计；展开面板提供按天统计用量情况、模型占比与部分估算成本，未知价格模型会明确标注未计入。也可用 `⌥⌘U` 切换完整面板。

## 效果演示

https://github.com/user-attachments/assets/e136c1a6-bc6f-487f-af30-b2dbc4bbde5f


## 特点

- **与刘海融合的灵动岛**：黑色 squircle 胶囊贴合物理刘海，右侧叠加 ChatGPT 六瓣花结图标与钴色光晕扫描，读作“ChatGPT 在线”。
- **三态丝滑过渡**：compact / peek / expanded 三态由 spring 动画驱动，形状先变、内容后现。
- **悬停即看**：光标进入胶囊区域自动展开 peek，展示周剩余额度与今日 Token；移出后自动收起，不打断工作流。
- **完整用量面板**：展开后可按天统计具体用量情况、模型占比和估算成本，未知价格模型明确标注未计入。
- **纯本机数据**：通过本机 Codex `app-server` 读取账号与额度，仅扫描本地 JSONL 聚合 Token，不保存提示词或回复正文。
- **零第三方依赖**：仅使用 Swift 标准库、Foundation、SwiftUI、AppKit 与 Carbon，应用与状态栏图标均为纯代码绘制。
- **全局快捷键**：`⌥⌘U` 随时切换完整面板，被占用时应用仍可用。
- **无障碍与减动效**：支持 VoiceOver 朗读与系统“减少动态效果”选项。

## 要求

- macOS 14 或更高版本。
- 目前仅适用于带有刘海的MacBook。
- 已安装 Codex CLI 或者 ChatGPT，确认已登录。Codex State 不会代替用户登录。

## 开发与打包

```bash
swift test
./Scripts/package_app.sh
open build/CodexState.app
```

打包脚本仅使用 Xcode Command Line Tools 和 macOS 系统命令：它会执行 release 构建、组装 `build/CodexState.app`，并使用 ad-hoc 签名，不下载依赖。

## 分发与安装

应用为 ad-hoc 签名（无 Apple Developer ID），通过 AirDrop / 下载 / 复制传到其他 Mac 时，Gatekeeper 会因隔离属性拒绝双击启动，提示“应用程序无法打开”。

**安装方式**：将 `CodexState.app` 拖入 `/Applications` 后，在终端执行：

```bash
xattr -cr /Applications/CodexState.app
```

移除隔离属性后即可双击运行。该命令只需执行一次，应用后续更新覆盖时若再次出现隔离属性，重新执行即可。

## 数据范围与隐私

- 应用启动本机 Codex `app-server` 子进程，仅读取已登录账号和当前额度；请求不刷新登录令牌。
- 本地用量只扫描 `CODEX_HOME` 下的 `sessions` 和 `archived_sessions` 目录；未设置 `CODEX_HOME` 时默认为 `~/.codex`。只聚合 JSONL 中的 Token 计数、模型和时间，不保存提示词或回复正文。
- 解析缓存位于 `~/Library/Caches/CodexState/usage-cache.json`，只包含聚合用量和文件指纹。
- 数据不会上传；应用不抓取网页、不读取浏览器 Cookie。

应用需要启动本机 Codex 子进程并读取已知日志目录，因此 MVP 不使用 App Sandbox，不通过 Mac App Store 分发。

## 成本估算

成本根据本地 Token 分类和 OpenAI API 公开模型单价估算，**不是 ChatGPT/Codex 订阅的实际账单或扣费金额**。未知模型仍会统计 Token，但不估算成本。

- 价格表更新日期：2026-07-22
- 官方价格来源：[OpenAI API Pricing](https://developers.openai.com/api/docs/pricing)
- 仓库价格表：`Sources/CodexStateCore/Pricing/Resources/ModelPrices.json`
