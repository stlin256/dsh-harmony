# Native Shell and Performance Consolidated E2E

Date: 2026-10-30

Status: pending device run. All implementation and local checks must finish before
this checklist is executed. Use `install -r` for the updated HAP so cookies,
Passkey state and app data remain available.

## Environment

- [ ] Verify the connected HarmonyOS device ID.
- [ ] Install `default` Release HAP with `install -r`.
- [ ] Install `store` Release HAP only on a separate test application identity
  or after backing up app data; never replace private cookies unexpectedly.
- [ ] Capture device model, API level, build/version and theme.
- [ ] Confirm the private service origin is not present in logs or screenshots
  intended for the public repository.

## Navigation and drawer

- [ ] Complete Passkey login and open a conversation.
- [ ] Kill the process and reopen. The last valid conversation restores before
  the workspace list becomes the landing surface.
- [ ] Confirm a notification/deep link target overrides the remembered session.
- [ ] Archive or remove the remembered session, reopen, and confirm the app falls
  back to the drawer without a broken chat.
- [ ] Open and close the drawer while a response is streaming.
- [ ] Confirm scroll position, draft, image draft, open process groups and input
  focus are retained behind the drawer.
- [ ] Verify drawer order: app name/search, new conversation, Plugins, Automation
  tasks, More, grouped workspaces, fixed Settings footer.
- [ ] Tap scrim, close button, system Back and edge gesture; each closes the
  drawer before leaving the app.
- [ ] Verify 84–88% phone width, safe-area padding, light/dark, large text,
  split-screen and rotation.
- [ ] Verify selected conversation, three-dot menu target and current workspace
  remain visibly highlighted.
- [ ] Expand/collapse workspaces, search, pin, drag reorder and manage a
  workspace.
- [ ] Confirm Plugins, Automation tasks and More each open a real destination or
  a precise compatibility handoff.

## Settings

- [ ] Confirm there are no horizontal tabs.
- [ ] Verify root destinations: DSH settings, appearance/motion, notifications,
  desktop cards, connection/account and About.
- [ ] System Back from every child returns to Settings root; Back from root
  closes Settings.
- [ ] Exercise every toggle, selector, text action and navigation row twice.
  No row may silently do nothing.
- [ ] Set each Host option, close Settings immediately, reopen, and verify the
  latest value and inline failure/retry behavior.
- [ ] Switch light/dark/system and verify every icon, text, surface, scrim,
  divider and control updates.
- [ ] Disable and re-enable reduce motion/transparency; verify the effect and
  unavailable explanation on unsupported API levels.
- [ ] Fast-tap independent settings while one write is pending; verify only the
  relevant row is pending.
- [ ] Verify Settings content sits above the bottom gesture area while the page
  background remains visible underneath it in both themes.
- [ ] Verify About shows bundled logo/avatar, author, app name, version/build,
  repository, issue link and copyright; all links open.

## Cache, reconnect and preload

- [ ] Open several substantial conversations, then kill/reopen the app.
- [ ] Confirm each previously opened conversation paints cached content before
  network refresh.
- [ ] Stop the network before opening a cached chat. Content remains readable;
  no false disconnected banner is shown during initial refresh.
- [ ] Trigger a real live connection failure; verify one compact banner,
  automatic reconnect and no duplicate manual retry text.
- [ ] Reconnect and verify newer messages merge without duplicates or
  resurrected replaced rows.
- [ ] Rapidly fling upward in a long conversation. Pages preload before the top;
  no repeated manual loading and no visible anchor jump.
- [ ] Confirm page requests do not duplicate during fast drag/reconnect.
- [ ] Open a 2,000-message synthetic/mock session and verify only a bounded
  window renders, scrolling remains responsive and message bodies stay complete.
- [ ] Verify code, reasoning, tools, images, tables and diff blocks survive cache
  restore.
- [ ] Open a cached transcript with the network disabled and verify previously
  resolved image bytes still render without a server request.
- [ ] Logout, sign in with another identity and confirm no prior transcript,
  route or card data appears.

## Markdown and footer

- [ ] Verify fenced code has language labels and colors in light and dark themes.
- [ ] Test JS/TS, JSON, shell, PowerShell, Python, Go, Rust, HTML/CSS, YAML, SQL,
  Markdown and diff examples.
- [ ] Copy each code block and compare it byte-for-byte with the source.
- [ ] Scroll long code horizontally and vertically on the phone.
- [ ] Verify 300–1,000-line code remains responsive and over-limit code falls
  back to readable plain text without truncation.
- [ ] Watch a streamed code reply settle; highlight must not jump the viewport.
- [ ] Verify the completed indicator and final-reply copy action share one
  compact row.
- [ ] Verify copy takes the final closing assistant reply, and does not appear
  for failed/stopped/no-final-reply turns or intermediate narration.

## Notifications

- [ ] For each category, set off/quiet/standard/prominent and trigger the event.
- [ ] Verify default: approval/failure standard, completion quiet, connection off.
- [ ] Verify Push server filters levels before enqueueing.
- [ ] Verify local background delivery applies the same matrix in the no-Push
  product.
- [ ] Deny system notification permission, then confirm Settings shows the
  effective degraded state and can open system settings.
- [ ] Tap notification in foreground, background and killed states; open the
  correct conversation.
- [ ] Verify duplicate event IDs deliver once and expired jobs do not arrive.
- [ ] Logout and verify device revocation and no later Push delivery.

## Desktop cards

- [ ] Add 2×2 and 2×4 cards.
- [ ] Trigger running, waiting, completed and failed transitions.
- [ ] Verify immediate/debounced refresh and bounded idle polling; no every-token
  updates.
- [ ] Toggle title privacy and confirm no task title/session ID leaks in card.
- [ ] Verify empty, loading, stale, offline and live states.
- [ ] Tap general and task links; route to drawer or exact conversation in warm
  and cold starts.
- [ ] Verify light/dark, large text and card instance update/removal.
- [ ] Logout and confirm card data clears or redacts.

## Performance evidence

- [ ] Record cache-first paint time.
- [ ] Record authoritative live snapshot time.
- [ ] Record transcript projection p50/p95.
- [ ] Record prefetch pages, dedup hits and long frames during fast scroll.
- [ ] Record memory after opening/evicting several large sessions.
- [ ] Record notification-to-visible and card-update latency.

## Exit criteria

- [ ] No settings row has silent no-op behavior.
- [ ] No cross-scope cache, credential, private hostname or signing data leaks.
- [ ] No known crash, ANR, unbounded render or repeated unauthored request loop.
- [ ] All fixed issues are rechecked on the same installed build.
- [ ] Version is bumped, tag is created, publication privacy check passes and the
  result is published without checking GitHub Actions.

