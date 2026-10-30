# Self-contained DSH Harmony plugin

## User requirement

The installed DSH Harmony Harness plugin must load after a Harness restart.
The remote plugin manager must not report:

```text
@dsh-harmony/plugin: failed
```

Installing the plugin must not depend on packages that happen to be installed
beside a development checkout. Existing login state, Harness sessions and
profile data must remain intact.

## Acceptance criteria

- The published plugin tarball includes the runtime dependency closure used by
  its nested gateway.
- Unpacking the tarball into an empty directory outside the repository and
  importing its host and browser entry points succeeds.
- The verification command tests the tarball itself, not a committed or stale
  development `node_modules` directory.
- The deployment installer rejects an incomplete release before switching the
  active release symlink.
- Build and deployment documentation describe the self-contained artifact.
- The fix contains no deployment hostnames, credentials, cookies or transcript
  data.
