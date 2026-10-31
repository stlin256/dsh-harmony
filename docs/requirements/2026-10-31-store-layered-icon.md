# AppGallery layered icon compliance

## User requirement

The AppGallery package now passes its ACL-sensitive build path, but the UX test
requires the application icon to follow the HarmonyOS layered-icon contract:

- a transparent foreground image;
- an opaque background image;
- both images at 1024 by 1024 pixels;
- no pre-cut rounded corners or baked-in border padding;
- the layered icon referenced by both the app and its home-entry Ability.

## Evidence

The cloud report identified the icon rule on two devices. The existing package
referenced a single 192-pixel SVG containing a rounded background and logo.

The Mate70 HiLog also confirms that the report was generated from the package
uploaded before the Store ACL fix. System `InitHapToken` failed with
`ERR_PERM_REQUEST_CFG_FAILED` because
`ohos.permission.ACCESS_FIDO2_ONLINEAUTH` had no valid ACL. The rebuilt Store
product removes that permission.

## Acceptance criteria

- The foreground and background are separate PNG resources.
- Both resources are exactly 1024 by 1024 pixels.
- The foreground has transparent corners and no opaque background.
- The background is a fully opaque, uniform DSH blue surface with no rounded
  corners.
- A layered-image resource references both files.
- `AppScope/app.json5` and both product manifests use the layered resource for
  the launcher entry.
- The visible brand remains recognizably the existing D mark with its mint
  accent.
- A reproducible script regenerates the two source layers and the preview.
- Both Store and default products build after the change.
