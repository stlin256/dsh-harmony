# AppGallery ACL-safe store variant

## User requirement

The current signed Store `.app` is rejected by AppGallery even though it is a
Release build. Resolve the package-check failure and keep the Store artifact
reproducible.

## Platform evidence

AppGallery reports one failed check:

- `ohos.permission.ACCESS_FIDO2_ONLINEAUTH` exists in the HAP.
- The same permission is absent from the release Profile.
- The remaining fourteen package checks pass.

The account can create a release certificate and release Profile, but the
AppGallery ACL page does not offer this restricted permission to the
application. This makes the manifest and release Profile inconsistent.

## Acceptance criteria

- The `store` Release product must not request FIDO2/Passkey system access.
- Its merged manifest must be ACL-consistent with the release Profile and pass
  AppGallery package checking after upload.
- The Store login surface must expose the supported native login flow and must
  not offer a Passkey option that cannot work with that package identity.
- A persisted Passkey selection must fall back to native login in the Store
  product.
- The `default` product keeps FIDO2/Passkey and Push Kit for the maintainer's
  self-signed build.
- Both products continue to build from the same shared ArkUI source.
- The variant rule is documented so a future contributor does not reintroduce
  the mismatch.
