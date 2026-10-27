# Next-session handoff — Folio Reader

## Where things stand (updated 2026-10-27)

Repository: https://github.com/Berrus/manga-reader-ios

- Everything from the old roadmap list is merged into `main` (PR #19 and earlier): merged editions, source migration, library and MangaDex recommendations, full-cover viewing, update notifications, private categories, AniList/MyAnimeList/Kitsu trackers, Suwayomi, OPDS (Kavita), comic EPUB, webtoon pinch zoom, paged zoom edge-chaining, opt-in iCloud sync and opt-in background downloads.
- Build and Test passed on 2026-10-27 (run 53, commit `398b09c`): iPhone tests, iPad tests, Mac Catalyst build and the App Store distribution job. Simulator tests do not replace real devices, servers or accounts.
- No IPA has been produced. Nothing has been tried on a physical device, a real Kavita/Suwayomi server, or real tracker accounts. The list of what still needs that is "Needs verification" in docs/FEATURE_STATUS.md.
- The AppStore configuration (`FolioReader-AppStore`) allows opt-in declarative sources and Suwayomi (`DistributionPolicy.allowsCustomSources`); that is a policy decision to revisit before submission.

## First tasks next session

- [ ] Read this file and docs/KOMIKKU-APPLE-ROADMAP.md, then inspect current main and any new contributor changes.
- [ ] Do not repeatedly consume GitHub Actions credits; commits can carry `[skip ci]`, and builds can be started by hand (`workflow_dispatch`).
- [x] Build/test current main on iPhone and iPad simulators, build Mac Catalyst, and run the AppStore source-boundary/privacy-manifest checks (passing, run 53).
- [x] Resolve compiler/test errors before claiming a passing build.
- [ ] When signing and macOS are available, archive/export an IPA and validate through TestFlight or the intended device-installation route.
- [ ] Preserve existing work and contributor history; do not overwrite concurrent changes.

## Remaining feature list

The features that used to be listed here are built (see above). What is still not built:

- [ ] **Native macOS target** — Mac Catalyst is the desktop target; a native port is assessed in docs/MACOS_NATIVE.md, not built.
- [ ] Reflowable (text) EPUB reader, and Kavita's native REST API (its OPDS feed works).
- [ ] Recommendations from sources other than MangaDex; broader cover-based theming.
- [ ] Widget and Shortcuts actions; localization catalogs.
- [ ] The monthly source-update pipeline and remote kill switch for sources.
- [ ] iCloud follow-ups listed in docs/ROADMAP_IMPLEMENTATION.md (stable identities, signed iCloud build, two-device validation).

## App Store release checklist

- [ ] Registered bundle identifier, signing team and distribution provisioning.
- [ ] Approved tracker client configuration and third-party service/content permissions.
- [ ] Published privacy policy and support URLs; accurate final privacy disclosures and age rating.
- [ ] Owned/licensed sample comics, covers and screenshots.
- [ ] Physical iPhone/iPad checks: gestures, rotation, Split View, offline relaunch, large libraries, memory/low storage, VoiceOver, Dynamic Type and Reduce Motion.
- [ ] IPv6-only networking, denied local-network permission, signed Release archive, dependency notices and final privacy report.
- [ ] TestFlight verification and review notes that accurately describe the submitted variant.

Apple approval is not guaranteed. Simulator tests do not establish App Store acceptance.

## Related documents and work

- docs/KOMIKKU-APPLE-ROADMAP.md
- docs/APP_STORE_SUBMISSION.md
- PR #8: https://github.com/Berrus/manga-reader-ios/pull/8
- PR #9: https://github.com/Berrus/manga-reader-ios/pull/9
- PR #10: https://github.com/Berrus/manga-reader-ios/pull/10
