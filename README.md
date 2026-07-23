# codex-state

Codex State 是一个原生 macOS 刘海用量工具。悬停查看剩余额度或今日统计；展开面板提供单屏趋势、模型占比与部分估算成本，未知价格模型会明确标注未计入。也可用 `⌥⌘U` 切换完整面板。

## 要求

- macOS 14 或更高版本。
- 已安装 Codex CLI，并通过 `codex login status` 确认已登录。Codex State 不会代替用户登录。

## 开发与打包

```bash
swift test
./Scripts/package_app.sh
open build/CodexState.app
```

打包脚本仅使用 Xcode Command Line Tools 和 macOS 系统命令：它会执行 release 构建、组装 `build/CodexState.app`，并使用 ad-hoc 签名，不下载依赖。

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

## 手工图形验收

以下项目需要在真实图形会话和对应硬件上执行，本次自动验证不代表它们已通过：

- [ ] 带刘海屏：静默态在顶部居中并贴合物理刘海。
- [ ] Hover：进入后延迟显示两项摘要，移出后延迟收起。
- [ ] 快捷键：`⌥⌘U` 可切换完整面板，被占用时应用仍可用。
- [ ] 无刘海屏：外接或主屏顶部居中显示黑色胶囊。
- [ ] 减少动态效果：开启系统选项后不执行尺寸动画。
- [ ] VoiceOver：摘要、数值、警告和收起按钮可正确朗读。
