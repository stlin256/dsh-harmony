# Self-contained plugin packaging specification

## Scope

The DSH Harmony plugin reuses the gateway source tree, whose runtime imports
`express`, `http-proxy`, `ws` and both SimpleWebAuthn packages. Harness plugins
installed through a profile `link:` resolve bare imports from the real linked
package path. Development-only dependency trees beside the repository cannot
satisfy those imports, and the Harness process cannot use `NODE_PATH` for ESM.

## Package contract

`scripts/package-plugin.mjs` creates a fresh staging directory and:

1. builds the browser factory;
2. copies the host entry, browser entry, notify module, gateway source and
   public assets;
3. merges the gateway production dependencies into the plugin manifest;
4. declares those dependencies as bundled dependencies;
5. installs only production dependencies without lifecycle scripts; and
6. runs `npm pack`.

The resulting tarball is relocatable. A profile may link to its unpacked
directory, or the Harness plugin manager may install it directly. Neither path
requires a separate dependency installation.

## Verification contract

`scripts/verify-plugin-package.mjs` accepts either a plugin directory or a
`.tgz` artifact. For a tarball it extracts into a new operating-system temporary
directory outside the repository, then verifies:

- the host entry imports;
- the browser client registers the expected module id;
- the gateway application constructs;
- the embedded authentication vendor asset and settings page respond with
  HTTP 200.

`package-plugin.mjs` invokes this verifier against the generated tarball. A
development tree containing installed dependencies therefore cannot produce a
false pass.

## Deployment guard

Before changing `/srv/dsh-harmony/current`, `deploy/install-pocket-id.py` imports
the staged plugin entry with the configured Harness Node.js runtime. A missing
module or syntax error stops installation while the previous release remains
active.

## Non-goals

- Changing Harness authentication.
- Migrating or deleting the profile database.
- Adding a sidecar process for the plugin.
- Publishing or reading user session content during deployment checks.
