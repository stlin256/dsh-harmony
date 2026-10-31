# AppGallery ACL-safe store variant implementation

## Product contract

| Product | Login modes | FIDO2 ACL | Push Kit |
| --- | --- | --- | --- |
| `default` | Native and Passkey | Requested and supplied by the self-signed development Profile | Included |
| `store` | Native | Not requested | Excluded |

The Store application identity must not advertise a capability that its
AppGallery release Profile cannot contain. The shared native login,
compatibility surface, session, file and notification code remains unchanged.

## Manifest selection

Hvigor uses `src/main/module.json5` as the module manifest for every normal
product target; the target source roots do not override it. Keep a Store
manifest at `harmony/variants/store/module.json5` with the same module structure
as `src/main/module.json5`, except that
`ohos.permission.ACCESS_FIDO2_ONLINEAUTH` is omitted.

The default product continues to use the main manifest, so it retains the
FIDO2 permission for local Passkey authentication.

`scripts/build-harmony.ps1` stages the Store manifest before a `store` build and
restores the canonical default manifest in a `finally` block. The staging file
is never left modified after a successful or failed build. IDE/devecocli builds
for AppGallery must use this wrapper so the compiled manifest matches the
release Profile.

## Capability selection

Add `ProductCapabilities` to the target-specific source roots:

- `src/personal/ProductCapabilities.ets`: Passkey supported.
- `src/store/ProductCapabilities.ets`: Passkey unsupported.

The shared login page imports `entry/ProductCapabilities` in the same way that
it imports the existing target-specific Push Kit adapter. This prevents a
runtime option from drifting away from the signed manifest.

When Passkey is unsupported:

1. Saved `passkey` mode resolves to `native`.
2. Connecting in `passkey` mode is rejected by resolving to `native` before
   endpoint discovery.
3. The Passkey selector is not rendered.

Store users that need Passkey must use a self-signed/default build whose
developer account is authorized to include the FIDO2 ACL in a release Profile.

## Verification

1. Parse both source manifests and assert only `default` requests FIDO2.
2. Build `default` and `store` Release HAPs.
3. Inspect each built HAP module manifest for the same permission contract.
4. Verify the Store `.app` embedded Profile is release, has no debug info and
   contains no FIDO2 ACL requirement.
5. Upload the rebuilt Store `.app` to AppGallery and require all package checks
   to pass before submission.

The device E2E table records Store login-mode visibility and default Passkey
preservation. AppGallery completion is recorded only after the portal check
reaches `通过`.
