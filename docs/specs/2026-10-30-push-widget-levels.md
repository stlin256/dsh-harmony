# Tiered Notifications and Desktop Cards Specification

Date: 2026-10-30

Requirements:
[PUSH-01 through PUSH-06 and CARD-01 through CARD-04](../requirements/2026-10-30-native-shell-performance.md)

Research:
[tiered notifications and cards](../research/2026-10-30-push-widget-levels.md)

## 1. Notification preference contract

Define a shared versioned matrix:

```text
approval:   off | quiet | standard | prominent
failed:     off | quiet | standard | prominent
completed:  off | quiet | standard | prominent
connection: off | quiet | standard | prominent
```

Defaults:

```text
approval=standard
failed=standard
completed=quiet
connection=off
```

Migrate legacy booleans:

```text
true  -> standard
false -> off
```

App and gateway validate the exact category and level allowlists. Unknown keys
or values are rejected. Device registration stores the same matrix shape.

## 2. Delivery

The canonical event payload is:

```text
version=1
eventId
category
level
sessionId
title
occurredAt
```

Rules:

- Server filters before enqueueing jobs.
- Local monitor filters with the same matrix.
- Deduplicate by `eventId`; retain the dedup lifetime through the existing
  one-hour job expiry and system `appMessageId` where available.
- Never include conversation body, file path, credential or raw origin.
- Preserve one-hour expiry, bounded retry and logout revocation.
- Validate `sessionId` on click and route from both warm and cold starts.

## 3. HarmonyOS slots

Use:

| Level | Slot |
| --- | --- |
| quiet | `CONTENT_INFORMATION` |
| standard | the application's normal service channel |
| prominent | `SERVICE_INFORMATION` when publishable |

Before publishing, query the slot. If the requested level is disabled or the
slot cannot be created, degrade to an available lower level. The Settings
notification page shows the effective level and a system-settings action rather
than claiming success.

Live-view notifications are out of scope unless a system proxy entitlement is
added. The app does not bypass Do Not Disturb.

For Push Kit, the server applies the matrix before delivery. Remote payloads use
only the approved category/entitlement and route metadata; an unavailable
prominent category degrades to standard.

## 4. Product variants

`default` with Push Kit:

- show the full category × level matrix;
- register/update the device matrix;
- remove the long-running background-monitor control;
- surface registration and system-channel state inline.

`store` without Push Kit:

- show the same category levels for local notifications;
- show a separate background-delivery row only when the user needs delivery
  while the app is not foreground;
- start monitoring only while a task is running, request notification
  permission, expose active/failed state and stop on disable/logout/idle;
- do not compile or request a Push token.

Both products share settings storage and validation; variant-specific controls
are capability-driven.

## 5. Settings UI

The Notifications child page has:

1. Category rows with compact four-way segmented controls.
2. Push registration or background-delivery status.
3. System channel state and an open-settings action.
4. A concise test notification row.

Each row owns pending/error state. Saving one category cannot disable unrelated
rows. Matrix save is atomic locally and remotely; on remote failure, retain the
local value, mark it unsynced and offer retry.

## 6. Card publication

Keep the existing 2×2 quick card and 2×4 overview card. Publish through the
single `WidgetStore` queue.

Update triggers:

- initial state/list load;
- task state transition;
- manual sync;
- foreground/idle poll at 30 seconds while active tasks exist;
- 60-second idle sync;
- app inactive: stop regular polling.

Debounce transitions by 1–2 seconds. Do not publish if the sanitized revision,
privacy mode and freshness bucket are unchanged. A failed refresh retains the
last good snapshot and marks it stale.

## 7. Card content

2×2:

- connection/freshness;
- most actionable action (`待确认`, then `运行中`);
- compact count;
- open the most relevant session when one exists, otherwise the drawer.

2×4:

- waiting and running counts first;
- up to four tasks, ordered waiting, running, failed, completed;
- task title only when privacy is enabled;
- short state label, freshness and direct open.

Future 4×4 can show up to six tasks and grouped recent results through the same
model. No form contains message content, filesystem paths, server URL or secrets.

States:

- empty;
- loading with last good data retained;
- connected/live;
- stale;
- offline;
- privacy-redacted.

Card colors use existing semantic light/dark resources. Task rows and actions
meet the minimum hit target. The UI remains readable with large text.

## 8. Deep links

Notifications and cards use validated `sessionId`. A warm app switches selection
without dropping an unsaved draft; a cold app resolves the target before falling
back to the last session. Invalid targets open the drawer with a compact reason.
A card request without `sessionId` opens the workspace drawer.

## 9. Tests and acceptance

Gateway/model tests:

- legacy migration and exact matrix validation;
- per-device filtering;
- event mapping, dedup, expiry, retry and logout revocation;
- payload allowlist and title redaction;
- no-Push local filtering parity;
- card revision/privacy/staleness/deep-link projections.

Consolidated device checks:

- `default`: trigger each event at each level, inspect channel behavior and tap
  from foreground/background/killed states.
- `store`: enable background delivery, run/fail/complete a task, verify start and
  stop behavior; disable and verify no further notifications.
- system channel denied: verify honest degraded state.
- both cards: add/remove, change privacy, trigger transitions, verify bounded
  update cadence, dark/light, stale/offline and direct routing.
- logout: remove devices, clear card data and prevent prior-session routes.

