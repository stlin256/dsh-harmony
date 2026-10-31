# Store showcase screenshot E2E

| ID | Scenario | Expected | Evidence |
| --- | --- | --- | --- |
| SHOT-01 | Build both Release products | Signed store and personal HAPs build successfully | Passed; store and personal signed HAPs produced |
| SHOT-02 | Normal app launch | No fixture client and no mock content are selected | Build and source inspection |
| SHOT-03 | Launch conversation in light | Native conversation renders deterministic content; model reads `DeepSeek-V4-Pro · 最高` | Passed on connected USB device; `raw/01-conversation-light.png` inspected |
| SHOT-04 | Launch process, sidebar and file browser in light | Each state opens directly in the native shell | Passed; screenshots 02–04 inspected |
| SHOT-05 | Launch settings in light | Native settings opens directly without login or private host | Passed; screenshot 05 inspected |
| SHOT-06 | Launch all five scenes in dark | Theme applies consistently with no unreadable controls | Passed; screenshots 06–10 inspected |
| SHOT-07 | Compose listing artwork | Ten scenes are generated in both orientations with rounded frames and compact composition | Passed; 20 listing PNGs plus two 10-image curated upload folders generated |
| SHOT-08 | Compose paired appearance artwork | Both orientations show light and dark captures side by side | Passed; 2 PNGs generated and inspected |
| SHOT-09 | Compose desktop cards artwork | Both orientations show source-matching light/dark cards with counts and task rows | Passed; 2 PNGs generated and inspected |
| SHOT-10 | Compose open-source artwork | Both orientations show the app logo and real repository URL without invented claims | Passed; 2 PNGs generated and inspected |
| SHOT-11 | File validation | Every PNG has expected dimensions and is under 5 MB | Passed programmatically for all 26 PNGs |
| SHOT-12 | Privacy scan | No deployment host, account, cookie or real transcript appears in output | Passed by source and output scan; marketing artwork crops system status and gesture chrome |
