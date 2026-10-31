# DSH Harmony store artwork

This directory is generated from deterministic Mock content on a connected
HarmonyOS device. It contains no deployment origin, account, cookie, token or
real transcript.

Refresh everything with one command:

```powershell
.\scripts\capture-store-screenshots.ps1 -Device '<device-id>'
```

The command builds the `store` Release product, installs it, captures the ten
Mock scenes, composes both orientations, validates dimensions and file size,
and writes `manifest.json`.

- `final/appgallery-landscape`: ten curated 1920×1080 PNGs
- `final/appgallery-portrait`: ten curated 1080×1920 PNGs
- `final`: the complete 26-image set, including unframed derivatives
- `raw`: real-device source captures

Use `-SkipBuild` to reuse the current signed store HAP and `-SkipInstall` to
capture with a HAP that is already installed. The model selection in Mock data
is `DeepSeek-V4-Pro` with `max` reasoning effort.

Pass `-RestorePersonal` to rebuild and reinstall the personal Push Kit variant
after the captures are complete.
