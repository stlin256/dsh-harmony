# Vendored optional OIDC gateway

Source: https://github.com/stlin256/harness-passkey-gateway

Revision: `f442a33294c4046929d48b4b9a95f4ad482a6d2b`

The original MIT license is retained in this directory. This optional gateway provides the Pocket ID OIDC entry in front of an existing Harness server. `../install-pocket-id.py` adds the versioned DSH Harmony adapter; the default native-login plugin does not require this gateway.

When updating, compare upstream changes to `src/server.mjs` with the installer's expected anchors and run the OIDC bridge security tests before deployment. No production configuration or credentials belong in this directory.
