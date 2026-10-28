# 与 Harness 的界面适配

本应用设置依据 NOTICE 中研究版本的以下原始样式适配：

- `packages/client/ui-theme/src/styles/base.css`：字体栈、4/8/12/16/20/28px 圆角，100/200/300ms 动画时长，以及 cubic-bezier(.4,0,.2,1) 曲线。
- `packages/client/ui-theme/src/styles/design-platform.css`：浅色白底、深色中性灰阶、主文本黑白反转、DeepSeek 蓝色强调。
- `packages/client/ui-settings-general/src/client/SettingsRoot.module.css`：188px 设置侧栏、800px 面板、28px 外圆角；窄屏改为全屏和横向导航。
- `packages/client/ui-primitives/src/settings-form/SettingsForm.module.css`：黑白主按钮、次级描边操作、紧凑分隔行。

设置页按通用、外观与动效、关于分组；通知开关及退出沿用真实接口。手机触控目标至少 44px，键盘具有可见焦点，状态消息使用 live region。深浅主题在样式加载前应用，避免设置页面初次渲染时先显示相反主题。

原生连接向导和顶栏使用相同中性色、12px 控件圆角、44/48vp 触控高度。退出置于设置中的连接管理，原生顶栏保留刷新与设置。原版 Harness 的 DOM、组件和业务设置不被重写。

`presentation.js` 仅在已信任源页面加载完成后安装观察器：读取 Harness 的 `body[data-ds-dark-theme]`，镜像到原生窗口和顶栏，并通过本地存储让应用设置沿用该主题。首次连接之前跟随系统；主题切换仍在 Harness 原版设置里完成。退出清理网页数据也会清理这些展示偏好。

动效采用 200ms 轻微淡入和 300ms 面板入场，按钮反馈使用 100ms 短过渡。遵循 `prefers-reduced-motion`，并提供额外的减少动态效果选项；两者任一开启即禁用入场、位移、开关过渡及加载旋转，操作忙碌时仍显示文字和禁用状态。没有给原版 Harness 强行注入全局动画规则。

## 验证

已使用本机 Chromium 对 320/390/768/1280px 四个宽度分别检查浅色与深色，共八种组合。检查无横向溢出、导航切换、减少动态效果持久化、系统减少动态效果及页面脚本错误，结果通过。页面状态接口在这次展示验证中使用测试数据，真实认证链路仍由服务端测试覆盖。

HarmonyOS 的字体实际渲染、安全区、系统栏明暗、ArkWeb 原生主题同步和触控手感仍需在真实设备按 VALIDATION.md 验收。没有执行 ArkTS/Hvigor 编译，也没有以浏览器截图代替原生验收。

## 原生系统表面与卡片

HarmonyOS 7 的材质限定在 Navigation 标题区和其中的原生操作控件；网页设置保留 Harness 中性视觉。卡片使用静态 ArkTS 布局和系统明暗资源，不叠加网页式模糊和持续动画。系统减少动效优先，减少透明与省电策略提供清晰回退。具体范围见 [HARMONY7.md](HARMONY7.md)。
