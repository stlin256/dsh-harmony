<p align="center">
  <img src="docs/assets/dsh-harmony.svg" width="96" height="96" alt="DSH Harmony">
</p>

<h1 align="center">DSH Harmony</h1>

<p align="center">
  <strong>把 DeepSeek Harness 装进 HarmonyOS</strong><br>
  原版能力，原生触感。为手机重新设计的 Harness 客户端。
</p>

<p align="center">
  <a href="https://github.com/deepseek-ai/deepseek-harness">
    <img src="docs/assets/deepseek.svg" width="22" height="22" alt="DeepSeek">
  </a>
  <a href="https://github.com/deepseek-ai/deepseek-harness"><strong>DeepSeek Harness</strong></a>
  &nbsp;·&nbsp;
  <img src="https://img.shields.io/badge/HarmonyOS-7-4D6BFE?style=flat-square" alt="HarmonyOS 7">
  <img src="https://img.shields.io/badge/API-23%2B-2EA44F?style=flat-square" alt="HarmonyOS API 23+">
  <img src="https://img.shields.io/badge/license-AGPL--3.0-6E7781?style=flat-square" alt="AGPL 3.0">
</p>

<p align="center">
  <a href="README.en.md">English</a> · <strong>简体中文</strong>
</p>

---

## 为手机而生的 Harness

DSH Harmony 将 DeepSeek Harness 的工作空间、会话、工具调用和实时输出带到 HarmonyOS。你可以保留原版网页的全部能力，也可以切换到为触控、键盘、安全区与系统返回重新设计的原生界面。

它关心的不只是“能不能用”。从冷启动到长对话滚动，从一次工具调用到一条后台通知，DSH Harmony 都围绕更少的等待、更清楚的状态和更自然的操作展开。

## 顺滑、简洁，也足够完整

| **顺滑** | **简洁** |
| --- | --- |
| 缓存先行、增量同步，历史内容提前预取；稳定列表与虚拟化渲染让长对话保持轻盈，页面切换和展开状态遵循 HarmonyOS 的节奏。 | 沿用 DSH 的紧凑信息层级与视觉语义。工具、思考、文件和消息保持清楚，但不让界面替内容抢戏。 |

| **原生触感** | **功能完整** |
| --- | --- |
| 触控反馈、抽屉、页面动线、安全区和系统 Back 都为 HarmonyOS 重新实现，并尊重系统的减少动态效果设置。 | 覆盖会话、模型、工具、审批、提问、图片、Markdown、代码、文件浏览与分级通知，让移动端真正完成工作流。 |

## 两种体验，一套工作空间

**兼容模式**完整呈现 Harness 原版网页、插件和高级控件。原生设置会无缝注入侧边栏，熟悉的界面不必被拆成两套产品。

**原生模式**用 ArkUI 重写高频工作流：会话列表、实时消息、工具步骤、审批、提问、模型选择、文件预览和图片灯箱都以 DSH 的视觉语言呈现。它会记住上次会话、工作区、滚动位置和展开状态。

登录同样保持灵活：

- **Harness 原生登录**是默认选项，可连接局域网或公网地址。
- **Pocket ID · Passkey**是可选选项，在 HTTPS 环境中使用系统 Passkey。

## 开始使用

1. 在 DeepSeek Harness 中安装本仓库发布的 DSH 插件。
2. 安装 DSH Harmony，填写 Harness 服务地址。
3. 选择原生登录或 Passkey，然后选用兼容模式或原生模式。

插件安装、服务部署与 Passkey 配置都在仓库文档中：

[插件指南](plugins/dsh-harmony/README.md) · [部署](docs/DEPLOYMENT.md) · [Passkey](docs/OIDC-DEPLOYMENT.md) · [界面模式](docs/UI-MODES.md)

## 连接状态，随时知道

任务完成、失败或等待确认时，DSH Harmony 可以按级别发送 HarmonyOS 通知。点击通知会回到对应会话；桌面服务卡片则以紧凑方式呈现工作区与任务状态。

个人构建支持使用 Push Kit 的即时推送。准备中的 AppGallery 版本会按应用商店能力单独构建，并在受系统约束的场景下提供后台状态监测。

## 即将登陆 AppGallery

<p align="left">
  <a href="https://developer.huawei.com/consumer/cn/appgallery/">
    <img src="docs/assets/huawei-appgallery.svg" width="34" height="34" alt="Huawei AppGallery">
  </a>
  <strong>HarmonyOS AppGallery · 准备中</strong>
</p>

我们正在准备面向所有 HarmonyOS 用户的商店版本。它会保留同样流畅的界面、完整的会话体验与 DSH 原生设计，并按照 AppGallery 的分发与通知规范持续更新。

## 参与共建

DSH Harmony 是开源项目。欢迎提交问题、改进建议和代码；开始开发前，请阅读 [验证说明](docs/VALIDATION.md) 与仓库中的实现规格。

[报告问题](https://github.com/stlin256/dsh-harmony/issues) · [查看源码](https://github.com/stlin256/dsh-harmony) · [作者主页](https://github.com/stlin256)

<p align="center">
  <sub>Built for HarmonyOS with care. AGPL-3.0.</sub>
</p>
