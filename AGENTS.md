# Repository Instructions

## Scope

DSH Harmony is a native HarmonyOS client and compatibility surface for DeepSeek
Harness. Preserve upstream behavior and identity while adapting layout for phone
touch, keyboard, safe areas and system Back.

## Required Workflow

For non-trivial UI or state changes:

1. Record the user requirement.
2. Research the current app and the pinned upstream reference.
3. Write or update a spec before production implementation.
4. Implement data contracts and correctness before decorative motion.
5. Add meaningful model/protocol tests.
6. Build both local and store product variants when shared ArkUI code changes.
7. Add or update the device E2E table. Do not claim device completion without
   actual device evidence.

Do not put private hosts, internal addresses, credentials, cookies, signatures,
or real transcript content in source, tests, docs, logs or commits.

## Design and Motion Rules

- Use the DSH visual language: compact information density, neutral surfaces,
  precise outlines, business glyphs and DeepSeek blue as the primary accent.
- Motion follows Quiet Precision: immediate press feedback, explicit spatial
  direction, interruptible direct manipulation, and no decorative loops.
- Streaming tokens, cache refreshes, incremental history and ordinary scroll
  entries must not play item entrance animation.
- Respect `NativeExperience.reducedMotion()`. All non-essential motion must
  resolve directly to the final state.
- Use semantic motion tokens instead of new one-off durations.
- API 26 materials are enhancements. API 23 must retain full function and
  hierarchy with opaque theme surfaces.

## Design, Spec and Evidence Index

- Visual baseline: [DESIGN.md](docs/DESIGN.md)
- Visual and motion design:
  [2026-10-31-dsh-harmony-visual-motion.md](docs/design/2026-10-31-dsh-harmony-visual-motion.md)
- Motion requirement:
  [2026-10-31-motion-workspace-pin-scroll-bottom.md](docs/requirements/2026-10-31-motion-workspace-pin-scroll-bottom.md)
- Motion implementation spec:
  [2026-10-31-motion-system.md](docs/specs/2026-10-31-motion-system.md)
- Pin, workspace ordering and scroll spec:
  [2026-10-31-workspace-pin-order-scroll-bottom.md](docs/specs/2026-10-31-workspace-pin-order-scroll-bottom.md)
- Self-contained plugin requirement:
  [2026-10-31-plugin-self-contained.md](docs/requirements/2026-10-31-plugin-self-contained.md)
- Self-contained plugin implementation spec:
  [2026-10-31-plugin-self-contained.md](docs/specs/2026-10-31-plugin-self-contained.md)
- Plugin activation recovery requirement:
  [2026-10-31-plugin-activation-recovery.md](docs/requirements/2026-10-31-plugin-activation-recovery.md)
- Plugin activation recovery implementation spec:
  [2026-10-31-plugin-activation-recovery.md](docs/specs/2026-10-31-plugin-activation-recovery.md)
- Plugin activation recovery device E2E:
  [2026-10-31-plugin-activation-recovery-e2e.md](docs/testing/2026-10-31-plugin-activation-recovery-e2e.md)
- Navigation and process refinement requirement:
  [2026-10-31-navigation-process-refinement.md](docs/requirements/2026-10-31-navigation-process-refinement.md)
- Navigation and process refinement spec:
  [2026-10-31-navigation-process-refinement.md](docs/specs/2026-10-31-navigation-process-refinement.md)
- Navigation and process device E2E:
  [2026-10-31-navigation-process-refinement-e2e.md](docs/testing/2026-10-31-navigation-process-refinement-e2e.md)
- HarmonyOS 7 motion research:
  [2026-10-31-harmonyos7-motion-strategy.md](docs/research/2026-10-31-harmonyos7-motion-strategy.md)
- Control motion audit:
  [2026-10-31-control-motion-audit.md](docs/research/2026-10-31-control-motion-audit.md)
- Pin, order and scroll research:
  [2026-10-31-workspace-pin-order-scroll-bottom.md](docs/research/2026-10-31-workspace-pin-order-scroll-bottom.md)
- Formal E2E checklist:
  [2026-10-31-motion-workspace-scroll-e2e.md](docs/testing/2026-10-31-motion-workspace-scroll-e2e.md)
- Settings surface, safe area and icon requirement:
  [2026-10-31-settings-safe-area-icons.md](docs/requirements/2026-10-31-settings-safe-area-icons.md)
- Settings surface implementation spec:
  [2026-10-31-settings-safe-area-icons.md](docs/specs/2026-10-31-settings-safe-area-icons.md)
- Store showcase screenshot requirement:
  [2026-10-31-store-showcase-screenshots.md](docs/requirements/2026-10-31-store-showcase-screenshots.md)
- Store showcase screenshot implementation spec:
  [2026-10-31-store-showcase-screenshots.md](docs/specs/2026-10-31-store-showcase-screenshots.md)
- Store showcase screenshot E2E:
  [2026-10-31-store-showcase-screenshots-e2e.md](docs/testing/2026-10-31-store-showcase-screenshots-e2e.md)
- AppGallery ACL-safe store variant requirement:
  [2026-10-31-store-acl-variant.md](docs/requirements/2026-10-31-store-acl-variant.md)
- AppGallery ACL-safe store variant implementation spec:
  [2026-10-31-store-acl-variant.md](docs/specs/2026-10-31-store-acl-variant.md)
- AppGallery ACL-safe store variant E2E:
  [2026-10-31-store-acl-variant-e2e.md](docs/testing/2026-10-31-store-acl-variant-e2e.md)
- AppGallery layered icon requirement:
  [2026-10-31-store-layered-icon.md](docs/requirements/2026-10-31-store-layered-icon.md)
- AppGallery layered icon implementation spec:
  [2026-10-31-store-layered-icon.md](docs/specs/2026-10-31-store-layered-icon.md)
- AppGallery layered icon E2E:
  [2026-10-31-store-layered-icon-e2e.md](docs/testing/2026-10-31-store-layered-icon-e2e.md)
- Chat controls and drawer requirement:
  [2026-10-31-chat-controls-refinement.md](docs/requirements/2026-10-31-chat-controls-refinement.md)
- Chat controls and drawer implementation spec:
  [2026-10-31-chat-controls-refinement.md](docs/specs/2026-10-31-chat-controls-refinement.md)
- Workspace file preview, mode switch, download and browser requirement:
  [2026-10-31-workspace-file-preview-browser.md](docs/requirements/2026-10-31-workspace-file-preview-browser.md)
- Workspace file preview implementation spec:
  [2026-10-31-workspace-file-preview-browser.md](docs/specs/2026-10-31-workspace-file-preview-browser.md)
- Workspace file preview and read-only E2E:
  [2026-10-31-workspace-file-preview-browser-e2e.md](docs/testing/2026-10-31-workspace-file-preview-browser-e2e.md)
- Sidebar scrollbar and browser-navigation requirement:
  [2026-10-31-sidebar-scrollbar-file-browser-navigation.md](docs/requirements/2026-10-31-sidebar-scrollbar-file-browser-navigation.md)
- Sidebar scrollbar and browser-navigation implementation spec:
  [2026-10-31-sidebar-scrollbar-file-browser-navigation.md](docs/specs/2026-10-31-sidebar-scrollbar-file-browser-navigation.md)
- Sidebar scrollbar and browser-navigation E2E:
  [2026-10-31-sidebar-scrollbar-file-browser-navigation-e2e.md](docs/testing/2026-10-31-sidebar-scrollbar-file-browser-navigation-e2e.md)
- Stability, settings feedback, notification prominence and composer inset
  requirement:
  [2026-10-31-stability-settings-notification-composer.md](docs/requirements/2026-10-31-stability-settings-notification-composer.md)
- Stability, settings feedback, notification prominence and composer inset
  implementation spec:
  [2026-10-31-stability-settings-notification-composer.md](docs/specs/2026-10-31-stability-settings-notification-composer.md)
- Stability, settings feedback, notification prominence and composer inset
  E2E:
  [2026-10-31-stability-settings-notification-composer-e2e.md](docs/testing/2026-10-31-stability-settings-notification-composer-e2e.md)
- Latest DSH stream recovery and native composer attachment requirement:
  [2026-10-31-stream-recovery-composer-attachments.md](docs/requirements/2026-10-31-stream-recovery-composer-attachments.md)
- Latest DSH stream recovery and native composer attachment implementation
  spec:
  [2026-10-31-stream-recovery-composer-attachments.md](docs/specs/2026-10-31-stream-recovery-composer-attachments.md)
- Latest DSH stream recovery and native composer attachment E2E:
  [2026-10-31-stream-recovery-composer-attachments-e2e.md](docs/testing/2026-10-31-stream-recovery-composer-attachments-e2e.md)
- Native interaction baseline:
  [NATIVE-INTERACTION-SPEC.md](docs/NATIVE-INTERACTION-SPEC.md)
- Existing shell/performance E2E:
  [2026-10-30-native-shell-performance-e2e.md](docs/testing/2026-10-30-native-shell-performance-e2e.md)
- HarmonyOS 7 platform notes: [HARMONY7.md](docs/HARMONY7.md)

## Upstream Tracking

- Upstream interaction reference is pinned in `docs/NATIVE-INTERACTION-SPEC.md`.
- Recheck the pinned revision before making an equivalence claim.
- Keep mobile-only extensions labeled as mobile extensions; do not present them
  as upstream behavior.

