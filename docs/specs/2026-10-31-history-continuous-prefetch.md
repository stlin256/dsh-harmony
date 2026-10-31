# 历史连续预取与分块缓存实现规范

日期：2026-10-31

状态：实现中。

## 分页状态机

`NativeHistoryRetryPolicy` 保存连续失败次数并返回语义化退避延迟：

1. 第一次失败等待 600 ms。
2. 后续依次等待 1200、2400、4800 ms。
3. 第五次及以后等待 8000 ms。
4. 任一页面成功后失败次数清零。
5. live snapshot 或网络恢复可显式 reset，并立即拉取下一页。

`NativeWorkspace` 不再以一次性的 `prefetchQueue` 作为主要历史加载驱动。选择会话
时建立 selection generation；live snapshot 启动 `historyDraining`。循环只在当前
组件挂载、会话 ID、selection generation、live 状态和服务端 `hasMore` 均仍有效
时继续。

自动页失败只进入退避计时器。401 仍交给统一认证路径。成功页写入缓存后等待约
40 ms 再取下一页，给 ArkUI 一帧更新 LazyForEach 和用户滚动的机会。

选择会话、`aboutToDisappear`、连接进入 syncing/retry、历史耗尽时清理计时器并将
当前 drain 标记为停止。已经发出的 HTTP 请求不可强删，但响应必须在写模型前再次
校验 selection generation 和 session ID。

页面必须产生可观察进展：

- 服务端返回 `hasMore=false` 即完成。
- `beforeSeq` 改变或可见行数量增加即成功。
- `hasMore=true` 但游标和行数都不变时抛出不前进错误，交回退避状态机。

用户滚动到顶部或点击“更早”时立即调用同一个 drain pump。若已有请求在途，点击
不会并发创建第二个分页请求。

## 缓存格式

新增两张表：

- `transcript_manifest(scope_id, session_id, chunk_count, updated_at, bytes)`。
- `transcript_chunk(scope_id, session_id, chunk_index, payload)`。

保存时同步捕获 `NativeSessionModel.capture()`，JSON 化后按 256 KiB UTF-16 字符
上限切块。切点不得落在 UTF-16 高代理项和低代理项之间。一个事务内删除旧块、
写入新块和 manifest，再删除可能的旧版单行 payload。

读取时先读 manifest，再按 `chunk_index` 拉取块并拼接解析。没有 manifest 时读取
旧版 `transcript_cache.payload`；旧行使用 `length(payload)` 与 256 KiB
`substr(payload,offset,length)` 分段读取，绝不一次取出整段大会话。旧缓存解析成功
后异步迁移为 manifest + chunk，下一次启动走新路径。读取失败或块数不匹配返回空
结果但保留原数据，避免一次瞬时 I/O 错误摧毁唯一可用缓存。退出、会话失效和配额
清理仍可显式删除。

配额以 manifest 的未压缩 JSON 字符数计量，并兼容旧单行记录。清理时同时删除两种
格式，活动会话和有待发送内容的会话保持保护。

## 消息复制

用户消息不再在气泡内渲染独立复制按钮行。长按有文本的用户气泡复制完整正文；
复制完成后沿用主题前景色和短时状态，不增加高度。最终助手答复继续由 turn footer
在同一行显示状态和复制按钮。

用户图片气泡继续只显示紧凑缩略图。打开后的 `NativeImageLightbox` 标题栏使用与
工作区图片预览相同的“标题 + 紧凑下载动作 + 关闭动作”顺序，下载动作调用现有
图库创建对话框；同一图片仍支持长按保存，避免改变已有手势。

## 测试与发布

- `gateway/npm test` 覆盖退避、进展判断、分块边界和现有协议回归。
- shared ArkUI 改动完成后分别构建 `default` 和 `store` Release。
- 真机先测弱网自动重试和快速切换，再测大历史第二次打开及向上锚点。
