# AppGallery layered icon implementation

## Resource contract

Store the source layers in `harmony/AppScope/resources/base/media`:

| Resource | Format | Required properties |
| --- | --- | --- |
| `app_icon_foreground.png` | RGBA | 1024 x 1024; transparent corners |
| `app_icon_background.png` | RGB | 1024 x 1024; one opaque DSH blue color |
| `app_layered_image.json` | JSON | foreground and background media references |

The background uses `#4176E6`. The foreground contains the existing white D
mark and mint accent without a background rectangle, rounded corners, mask, or
additional exported frame.

## References

`AppScope/app.json5` references `$media:app_layered_image`. The main and Store
module manifests use the same resource for `EntryAbility`, because a module
Ability icon takes precedence over the AppScope icon.

## Reproducibility

`scripts/generate-layered-icon.py` recreates both PNG layers and the composed
preview with Pillow. It samples the existing SVG geometry at four times the
target size and downsamples to retain smooth edges. The script fails when:

- either layer has the wrong dimensions;
- the background is not fully opaque;
- the foreground corners are not transparent;
- the foreground has no transparent pixels; or
- the background contains more than one color.

Run:

```powershell
python scripts/generate-layered-icon.py
node scripts/verify-harmony-product-variants.mjs
```

For API 23, the DevEco resource pipeline re-encodes the runtime copies inside
the HAP at 512 by 512. Keep the canonical 1024 by 1024 files in `AppScope`;
the compiled copies are build intermediates and must not be copied back into
source.

## Build boundary

The icon layer is shared by both product variants. The Store build continues
to use the ACL-safe manifest staging wrapper; the default build retains the
self-signed Passkey capability.
