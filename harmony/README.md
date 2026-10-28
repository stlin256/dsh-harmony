# DSH Harmony 移动端

![DSH Harmony](AppScope/resources/base/media/app_icon.svg)

[English](README.en.md)

HarmonyOS 原生工程位于本目录。仓库根目录 README 提供产品、登录、插件和通知说明；本页聚焦构建与签名。

## 构建产品

| 产品 | Push Kit | 后台通知 | 用途 |
| --- | --- | --- | --- |
| `default` | 包含 | 由 Push Kit 送达 | 作者自用签名版；服务器插件使用项目服务帐号推送 |
| `store` | 不包含 Push Kit SDK | 可选监测运行中任务 | 应用商店及普通开发者构建 |

两个产品的应用名均为 **DSH Harmony**，bundle name 为 `io.github.stlin256.dshharmony`。需要在 Huawei 开发者中心登记这个应用后，才能为该应用申请应用签名和 Push Kit 能力。此仓库不保存应用签名、服务帐号或开发者凭据。

## 本机构建

1. 使用包含 SDK 26 的 DevEco Studio。
2. 将 `build-profile.example.json5` 复制为本机忽略的 `build-profile.json5`，填入开发者中心签名配置；保留个人密钥在 Git 之外。
3. 在 Harmony 工程目录执行：

```sh
devecocli signature generate --product default
devecocli signature generate --product store
devecocli build --product default --build-mode release
devecocli build --product store --build-mode release
```

安装到当前设备可执行 `devecocli run --module entry@default --product default --build-mode release --skip-build`。产品产物分别位于 `entry/build/default/outputs/default/` 和 `entry/build/store/outputs/store/`。

## 通知

服务端 DSH 插件保存任务名与匿名状态投影。`default` 版以 Push Kit 分别发送任务完成、失败和待确认提醒。`store` 版不获取 Push Kit token；用户开启“任务运行时后台监测”后，应用只在检测到运行中任务时申请系统可见的长时任务，轮询状态，任务完成后停止。通知点击会打开对应会话。

不要将真实服务地址、凭据、签名 Profile 或 Push Kit 服务帐号提交到仓库。
