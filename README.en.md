# DSH Harmony

![DSH Harmony](harmony/AppScope/resources/base/media/app_icon.svg)

Native interaction work follows the [source-backed specification](docs/NATIVE-INTERACTION-SPEC.md). The [implementation ledger](docs/NATIVE-INTERACTION-STATUS.md) distinguishes implementation, automated checks, and device validation.

[简体中文](README.md) · English

A HarmonyOS companion for [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness). Compatibility mode preserves the original Web workspace. The experimental native interface provides sessions, messages, tools and live interactions, with system notifications and home-screen widgets.

## Login options

| Method | Server requirements | App input |
| --- | --- | --- |
| **Native login — default** | Harness and this repository's single DSH plugin | Web origin and Harness access key |
| **Pocket ID / Passkey — optional** | The plugin and a Pocket ID OIDC entry | Workspace HTTPS origin and system Passkey |

Native login uses Harness's official launch-token exchange and signed cookies. No separate relay or companion daemon is required. HTTP and HTTPS are supported. Pocket ID requires HTTPS. Both methods support LAN and public deployments. Login method and interface mode are separate choices.

## Getting started

1. Prepare a reachable Harness Web instance on Node.js 24.9+.
2. Run `npm ci` in `gateway/`, then `node scripts/package-plugin.mjs` from the repository root.
3. Install `.artifacts/dsh-harmony-plugin-0.2.3.tgz` using Harness's plugin manager and enable `@dsh-harmony/plugin`. See the [plugin guide](plugins/dsh-harmony/README.md) for manual installation.
4. Install the app. Use the default native login with the Web origin and access key from the startup URL's `token` parameter. The key is not saved in app preferences; the signed cookie is used for later sessions.
5. Optional Pocket ID setup instructions and tools are in the [Passkey deployment guide](docs/OIDC-DEPLOYMENT.md). Choose the lower Passkey option after configuring the server.

Configure binding, trusted hosts, port forwarding and TLS for your environment. See [deployment](docs/DEPLOYMENT.md).

## Features and status

- Original Web workspace, plugins and advanced interactions in compatibility mode.
- Experimental native sessions, text/images, tools, models, queues, approvals, questions and live output. See [interface modes](docs/UI-MODES.md) and [coverage](docs/NATIVE-COVERAGE.md).
- Native chat uses DSH glyphs and a compact layout, formats message text, hides empty sessions, and retains loaded history across reconnects.
- Local theme, motion and connection settings; a failed or offline login can still be exited.
- Entry and task overview widgets with task names and timestamped local snapshots.
- Task/approval collection and a durable SQLite notification queue. The personal Push Kit build supports notification levels; the AppGallery build omits Push Kit and can optionally monitor active tasks in the background.

SDK 26, API 23 compatibility. The `default` and `store` products build the personal Push Kit and AppGallery variants. See the [mobile build guide](harmony/README.md).

## Development

[Plugin](plugins/dsh-harmony/README.md) · [Deployment](docs/DEPLOYMENT.md) · [Pocket ID](docs/OIDC-DEPLOYMENT.md) · [HarmonyOS 7](docs/HARMONY7.md) · [Validation](docs/VALIDATION.md)

Run `npm ci && npm test` in `gateway/`. The native project is in `harmony/`; optional authentication tooling is in `deploy/`. `gateway/` contains modules reused inside the plugin and does not need to run separately. Keep signing configuration, deployment addresses, service accounts and user data outside Git; run `node scripts/check-publication.mjs` before publishing.

[AGPL v3](LICENSE); see [NOTICE](NOTICE). The optional OIDC gateway retains its [MIT license](deploy/pocket-id-gateway/LICENSE) and [upstream revision](deploy/pocket-id-gateway/UPSTREAM.md).
