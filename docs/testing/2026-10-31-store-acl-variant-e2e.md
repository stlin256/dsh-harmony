# AppGallery ACL-safe store variant E2E

| ID | Scenario | Expected | Evidence |
| --- | --- | --- | --- |
| ACL-01 | Inspect the rejected Store package check | Only ACL declaration consistency fails; HAP has FIDO2 and Profile does not | Passed; AppGallery reported item 1 failed and items 2-15 passed |
| ACL-02 | Inspect Store source manifest | FIDO2 is absent; native login and non-ACL capabilities remain | Passed; `harmony/variants/store/module.json5` contains only `INTERNET` and `KEEP_BACKGROUND_RUNNING` |
| ACL-03 | Inspect default source manifest | FIDO2 remains present | Passed; `harmony/entry/src/main/module.json5` retains `ACCESS_FIDO2_ONLINEAUTH` |
| ACL-04 | Build both Release HAPs | Both products compile from shared ArkUI code | Passed; Store and default both completed `devecocli build --build-mode release` |
| ACL-05 | Inspect built HAP manifests | Store omits FIDO2; default includes it | Passed; Store contains `INTERNET` and `KEEP_BACKGROUND_RUNNING`; default additionally contains `ACCESS_FIDO2_ONLINEAUTH` |
| ACL-06 | Verify Store signing | Profile type is release, debug info is absent and bundle identity matches | Passed; `hap-sign-tool verify-app` and `verify-profile` succeeded for the Store HAP; Profile is `release`, Bundle is `io.github.stlin256.dshharmony`, and App ID is `6917620534098659305` |
| ACL-07 | Launch Store login on device | Only native login is offered; a saved Passkey mode resolves to native | Pending |
| ACL-08 | Launch default login on device | Native and Passkey options remain available | Pending |
| ACL-09 | Upload rebuilt Store `.app` | AppGallery package check passes the ACL item and all other required checks | Pending |
