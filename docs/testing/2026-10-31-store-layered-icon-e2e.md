# AppGallery layered icon and package E2E

| ID | Scenario | Expected | Evidence |
| --- | --- | --- | --- |
| ICON-01 | Inspect the previous cloud UX report | The only UX failure is the non-layered launcher icon | Passed; report identified the layered 1024 x 1024 icon rule on Mate X7 and Mate 60 Pro |
| ICON-02 | Decompress and inspect the Mate70 package-install log | Both affected devices share the same ACL failure | Passed; `InitHapToken` reported `ERR_PERM_REQUEST_CFG_FAILED` for `ACCESS_FIDO2_ONLINEAUTH` |
| ICON-03 | Generate foreground and background resources | Both are 1024 x 1024 and meet transparency rules | Passed; generator validation reports transparent foreground corners and a fully opaque uniform background |
| ICON-04 | Inspect app and Ability icon references | Both resolve to the layered-image resource | Passed; `AppScope/app.json5`, the default manifest and the Store manifest reference `$media:app_layered_image` |
| ICON-05 | Build Store and default products | Both products compile from the updated manifests | Passed; both Release builds completed with `devecocli build` |
| ICON-06 | Inspect the rebuilt Store HAP | It contains the layered resources and omits the FIDO2 ACL | Passed; the HAP contains both layer PNGs and `app_layered_image.json`, requests only `INTERNET` and `KEEP_BACKGROUND_RUNNING`, and its release signature validates |
| ICON-07 | Upload and run the AppGallery UX test | No installation or icon-rule failure remains | Pending device evidence |

Current local upload candidate:
`harmony/build/outputs/store/harmony-store-signed.app`

SHA-256:
`A48499906B61155B4CBD9740BBAFCBFD6AB4C011E96A978AF3C25FB99A2F63AA`
