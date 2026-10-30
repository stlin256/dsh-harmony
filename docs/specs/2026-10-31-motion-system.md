# HarmonyOS 动效系统实现规格

日期：2026-10-31

状态：本地实现；自动化与 Release 构建已通过，真机 E2E 待执行。视觉基线见
[DSH Harmony 视觉与动效设计](../design/2026-10-31-dsh-harmony-visual-motion.md)。

## 1. 架构

新增 `NativeMotion` 服务作为唯一语义入口：

- `NativeMotion.animate(ui, token, action)`：普通确定性动画。
- `NativeMotion.rowTransition()`、`overlayTransition()`、`navigationTransition()`：常用
  组合转场。
- `NativeMotion.spring(ui, action)`：需要低回弹落位的少量空间变化。
- `NativeMotion.enabled()`：统一读取 `NativeExperience.reducedMotion()`、前台和低电量
  策略。

组件不得直接新增 `180`、`200`、`210` 等时长常量；已有调用在触达相关控件时迁移到
语义 token。动画只负责表现，写入成功、导航完成、消息提交和排序确认不等待动画回调。

所有 `TransitionEffect` 通过 `.animation(NativeMotion.implicit(token))` 绑定时长和
曲线。导航 token 接受方向参数，页面根层级与二级页面使用相反方向的 X 位移。

## 2. 状态与方向

### 页面

- 设置根页到二级页：进入 `x: 10`、`opacity: 0 -> 1`，220ms。
- 二级页返回：退出 `x: 10`、`opacity: 1 -> 0`，180ms。
- 系统 Back 调用与页面返回按钮相同的导航方法。
- 抽屉内容只在打开/关闭边界播放；聊天子树保持挂载。
- 抽屉打开和关闭都支持跟手位移；遮罩透明度由同一抽屉进度计算。

### 浮层

- 菜单和模型气泡：`opacity` + `scale 0.98 -> 1`，190ms。
- 浮层退出使用 140–160ms；退出过程中不接收新的业务动作。
- Popup/Sheet 系统容器已有动效时，内容只补充 opacity，避免双重大位移。

### 控件

- 原生 `Button` 状态效果保留；自定义透明按钮必须提供按压背景或轻 scale。
- 展开箭头和内容共用一个状态更新；不对同一内容再追加第二段滚动。
- 可复制图标在 140ms 内切换到 check，并从状态更新开始计时恢复。
- 图片捏合期间直接更新 scale，不在每个 gesture update 中启动新的动画。

## 3. 减少动态效果

`NativeExperience.reducedMotion()` 为 true 时：

- `NativeMotion.animate()` 同步执行 action，不创建动画时钟。
- 所有 transition 返回 `TransitionEffect.IDENTITY`。
- 回到底部直接定位；抽屉直接切换；列表结构变化直接替换。
- 状态文字、忙碌指示、错误和选中颜色仍立即更新。

## 4. API 版本与系统策略

- API < 26 不构造材质对象。
- 减少透明度、低电量、应用后台或材质服务禁用时使用主题实色。
- spring 参数集中定义；响应式弹簧使用 SDK 推荐默认值。
- 不为装饰目的使用 `motionBlur` 和持续材质交互光效。

## 5. 验收

- 自动化验证 helper 在正常和减少动效状态下的时长、曲线和终态。
- ArkTS Release 构建必须通过 `default` 和 `store`。
- 真机按 E2E 表检查抽屉反向拖动、菜单中断、快速连续点击、流式阅读和 API 23/26
  表面差异。

## 6. 本地实现证据

- `node --test`：71/71。
- 语义 token、减少动效旁路和 `TransitionEffect` 时长由模型测试覆盖。
- `default` 与 `store` Release HAP 构建均通过。
- 真机 E2E 尚未执行，不能将上述自动化证据等同于真实触感和性能验收。

