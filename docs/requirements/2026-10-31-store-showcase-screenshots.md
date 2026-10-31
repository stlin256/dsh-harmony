# Store showcase screenshots

## User requirement

Provide the signed AppGallery HAP, then capture the native app UI on a real
HarmonyOS device with deterministic mock content. The screenshots will become
AppGallery listing artwork and must not expose a private host, account, cookie,
signature or real transcript.

## Acceptance criteria

- The normal application launch remains unchanged.
- A launch-only flag can open the native shell with synthetic sessions,
  workspaces and a representative conversation.
- Conversation, expanded process, sidebar, file browser and settings screens
  can be selected independently for capture.
- Light and dark appearances can be selected independently for capture.
- The mock model selection uses the upstream identity `DeepSeek-V4-Pro` with
  the supported `max` reasoning effort rather than a legacy reasoner label.
- Mock content contains no deployment address or user data.
- The capture helper produces real-device screenshots in both light and dark
  appearances, framed by rounded device outlines.
- The promotional set also includes paired light/dark appearance artwork,
  desktop-card artwork and open-source project artwork.
- The artwork is compact: the device frame and copy occupy the canvas as one
  dense visual block, with no large empty field around a small phone.
- Every promotional image is available at exactly 1920×1080 and 1080×1920,
  remains below AppGallery's 5 MB limit and contains no private data.
- Evidence records the device, build version, HAP and capture result.
- The `store` HAP remains installable and contains no Push Kit adapter.
