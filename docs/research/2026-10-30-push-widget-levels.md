# Tiered Notifications and Desktop Cards Research

Date: 2026-10-30

Requirements: PUSH-01 through PUSH-06 and CARD-01 through CARD-04

## 1. Current implementation

### 1.1 Notification preferences are boolean

The app, gateway and device registration currently store three booleans:

```text
completed
failed
approval
```

The gateway emits jobs only for `run.completed`, `run.failed` and
`permission.required`, and filters each device with those booleans. The app
stores the same shape in Preferences. The no-Push variant additionally supports
a single `backgroundMonitor` preference.

There is no representation of quiet delivery, standard delivery, or a stronger
alert. The local notification path uses the system default slot and cannot make
the user's choice deterministic.

### 1.2 Push behavior

`createPushSender()` sends a Huawei Push Kit notification payload with a title,
category and click data. Delivery retries are bounded to eight attempts and jobs
expire after one hour. Notification clicks already carry `sessionId`; cold-start
and warm-start routing are implemented by `EntryAbility`.

The store-oriented product compiles a no-op Push Kit adapter. Its background
monitor polls while tasks are running, publishes a local notification and stops
when the task state settles. Both products therefore share the same event
categories but have different delivery availability.

### 1.3 Desktop cards

There are two static forms:

- `PocketQuick`, 2×2, connection/headline entry.
- `PocketOverview`, 2×4, status counts and up to four task rows.

The active app polls `/pocket/api/overview` every 60 seconds and uses
`formProvider.updateForm()` to republish a sanitized snapshot. The card data has
timestamp expiry, task-title privacy and app replacement. It currently lacks
explicit lifecycle debounce, a stable card update reason, a complete compact/
medium/expanded state model and a responsive privacy-first layout.

## 2. HarmonyOS notification levels

The API 23 notification slot model exposes:

| Slot type | System level | Effective presentation |
| --- | --- | --- |
| `CONTENT_INFORMATION` | `LEVEL_MIN` | Notification center, no status icon, sound or banner |
| `OTHER_TYPES` | `LEVEL_MIN` | Generic low-priority entry |
| `LIVE_VIEW` | `LEVEL_DEFAULT` | Reserved for system-proxied live views |
| `SERVICE_INFORMATION` | `LEVEL_HIGH` | Status icon, alert and banner |
| `SOCIAL_COMMUNICATION` | `LEVEL_HIGH` | Status icon, alert and banner |

An app creates one slot per type. The user's system channel settings override
the app's requested intensity. A third-party app cannot create an arbitrary
custom level or a general live view.

Consequences:

- Quiet maps to `CONTENT_INFORMATION`.
- Standard maps to a normal event slot with system-level behavior available to
  this app; it must not claim low/default distinction if the channel is capped.
- Prominent maps to `SERVICE_INFORMATION` only for urgent approval/failure
  choices. The app reports the actual channel level and degrades when the user
  disabled it.
- Live-view UI is not part of this scheme because it requires system proxy
  rights.

For Push Kit payloads, the app cannot retroactively change the OS rendering of a
remote notification after delivery. The server must apply the device tier before
enqueueing, and the payload carries only allowlisted routing metadata. Prominent
remote delivery remains capability/entitlement dependent and must degrade to the
normal category.

## 3. Recommended preference matrix

Categories:

- approval input required;
- task failed;
- task completed;
- connection/background notice (optional and off by default).

Levels:

- `off`;
- `quiet`: appears in the notification center without sound/banner;
- `standard`: system notification behavior;
- `prominent`: alerting where the installed OS/application entitlement permits.

Initial defaults:

| Category | Default | Rationale |
| --- | --- | --- |
| Approval input | Standard | User action is required, but defaults should remain respectful |
| Task failed | Standard | Action may be needed, with no silent omission |
| Task completed | Quiet | Useful history without interrupting other work |
| Connection | Off | Prevents noise and duplicate transport retries |

The settings UI shows one row per category with a compact segmented selector.
Changing a row applies immediately, persists locally and syncs the same matrix
to every registered Push device. If Push is unavailable, only connection/
background delivery controls are shown.

## 4. Delivery contract

The canonical payload is:

```json
{
  "version": 1,
  "eventId": "<stable event id>",
  "category": "approval|failed|completed|connection",
  "level": "quiet|standard|prominent",
  "sessionId": "<allowlisted id>",
  "title": "<short task title>",
  "occurredAt": 0
}
```

Rules:

- `eventId` deduplicates local and Push delivery for 24 hours.
- Server filters by the current device matrix before creating a job.
- App filters local notifications with the same matrix.
- Bodies contain only short task title/status, never conversation content.
- `sessionId` is required; click routing validates it before opening.
- Job expiry and retry/backoff remain server-owned.
- Logout revokes devices and clears local notification preferences.
- Unsupported "prominent" becomes the strongest channel the app can access and
  displays that effective level in Settings.

## 5. Card update model

Use event-driven convergence with bounded polling:

1. Update immediately after state/session list load.
2. Update when an observed run enters/leaves `running`, `waiting`, `completed`
   or `failed`.
3. Debounce event-triggered refreshes for 1–2 seconds.
4. Poll every 30 seconds only while the app is foreground and the overview has
   active/waiting tasks.
5. Poll every 60 seconds while connected and idle.
6. Stop polling when inactive; run the existing bounded background-monitor path
   only in the no-Push product when the user enabled it.
7. Never update on every transcript token or message delta.

All forms publish through `WidgetStore`'s single writer queue. Skip publication
when the sanitized state revision and privacy mode are unchanged.

## 6. Card information priorities

| Size/state | Priority |
| --- | --- |
| 2×2 compact | connection state, waiting/running count, first actionable task |
| 2×4 medium | state counts, up to 4 task rows, last sync, direct open |
| expanded | up to 6 rows, grouped waiting/running/recent, task detail route |

The existing form profile exposes 2×2 and 2×4. Implementation starts with those
two sizes; expanded behavior is specified for future 4×4 support.

States:

- Empty: connect or create a task.
- Loading: cached card remains visible with a subtle refreshing indicator.
- Offline: stale badge and direct retry/open.
- Stale: snapshot older than 15 minutes; hide titles first.
- Privacy off: no titles or session IDs in rendered card.
- Light/dark: semantic resources and theme-specific contrast.

Every card link uses the same validated `sessionId` as notifications and the
drawer. A general action opens the workspace drawer; a task action opens the
conversation.

## 7. Validation

Gateway tests:

- preference migration from booleans;
- matrix validation and per-device filtering;
- event deduplication and category mapping;
- payload allowlist and no body content;
- logout/device revocation and bounded retry/expiry.

App/model tests:

- preference migration and local/Push parity;
- click routing for warm and cold start;
- channel fallback and unpublishable notification;
- card sanitization, privacy toggles, stale/offline reasons;
- skip unchanged publication and debounce lifecycle events.

Consolidated E2E:

- set each category to off/quiet/standard/prominent and trigger each event;
- verify Push and no-Push products separately;
- tap notifications from warm and killed app states;
- verify system-disabled channels degrade with visible settings feedback;
- add both cards, trigger run/wait/finish/fail and inspect update latency,
  privacy, dark/light and each deep link;
- verify cards clear or redact on logout.

