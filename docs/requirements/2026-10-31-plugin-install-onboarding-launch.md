# Plugin Installation, Onboarding and Branded Launch

Date: 2026-10-31

Status: implementation requested.

## User Requirements

- `ONBOARD-01` Make plugin installation approachable for a normal DSH user.
  A user must be able to send DSH one short prompt or provide the project link
  and let the DSH agent complete the documented installation.
- `ONBOARD-02` The project must publish a DSH-compatible bundle artifact with
  the patch metadata, production dependency closure, browser entry, host entry
  and version needed by the official plugin manager.
- `ONBOARD-03` A first launch shows a polished welcome surface: centered logo,
  product name and two full-width actions, one for the guide and one to enter
  directly.
- `ONBOARD-04` Entering the guide moves the logo into a lower-right watermark
  with a restrained enlarge/fade transition. Three concise illustrated steps
  explain where to install the plugin in DSH and how to connect the app.
- `ONBOARD-05` The guide provides a repository action and a single copy action
  for the installation prompt. The prompt must not depend on private hosts or
  credentials.
- `ONBOARD-06` The same welcome flow appears after logout when the app is opened
  again, while the previous service address remains prefilled for convenience.
- `LAUNCH-01` A cold launch never exposes the address and login form before
  saved-session restoration has settled. A branded launch animation occupies
  that interval.
- `LAUNCH-02` If a saved session restores successfully, the launch surface
  transitions directly into the workspace. If authentication is required, the
  user reaches the login form from the same visual system.
- `LAUNCH-03` Restore and login failures use the launch visual language. The
  error is readable, copyable and recoverable through retry or address editing.
- `LAUNCH-04` Passkey remains below the default native-login option. Passkey
  and native login behavior, HTTPS requirements, notification deep links and
  existing workspace entry behavior remain compatible.

## Constraints

- Follow the repository's Quiet Precision motion rules and reduce-motion
  preference.
- Keep copy short. Do not add long explanatory paragraphs to login or normal
  app surfaces.
- Do not include deployment hosts, credentials, cookies, signing material or
  real transcript content in source, tests, documentation or commits.
- Keep the plugin in this repository unless a separately versioned protocol
  makes extraction necessary. App and plugin protocol versions currently need
  to move together.

## Acceptance Criteria

- Packaged plugin metadata declares `dsh.bundle.patch`; a cold extraction from
  the tarball imports successfully and contains its production dependencies.
- The stable installation prompt resolves to a documented release artifact and
  remains usable when pasted into DSH.
- First launch and post-logout launch show the welcome flow. A successful saved
  session bypasses it and enters the workspace.
- Login restoration, manual native login, Passkey login, error copy, retry and
  address editing all remain functional.
- Light, dark, reduced motion, API 23 and API 26 surfaces preserve hierarchy
  and readability.
- Both `default` and `store` Release variants build.
- Device E2E evidence is recorded before any device row is marked complete.
