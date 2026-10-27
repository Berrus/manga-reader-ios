# Next-session handoff — Folio Reader

## User's latest instruction

Save the remaining roadmap features as a list for the next session. Do not treat this handoff as evidence that these features have been implemented.

Repository: https://github.com/Berrus/manga-reader-ios
Baseline main commit when this handoff was written: 60bf1d81a4406c19304207bafaea18179105d3e0

## Current status

- PR #8 merged: saved searches, library reading/offline filters, last-read sorting, and bulk category moves.
- PR #9 merged: five accent palettes, dark cover-derived reader backgrounds, webtoon autoscroll, preload and image-cache controls.
- PR #9's final head `79f03d1` passed 64 unit tests and seven UI tests on each of iPhone and iPad (71 per device); Mac Catalyst built successfully.
- PR #10 is merged: saved-query feed, grouped updates, update errors/progress, privacy declarations, and a separate FolioReader-AppStore configuration.
- PR #10's latest code is NOT validated. An earlier LibraryView type-checking failure was patched, but the latest checks and retry failed before runners executed any steps. Do not describe the current main build as passing.
- The user reports exhausted GitHub usage credits and has no Mac available right now.
- No IPA has been produced. Actual iOS compilation, signing and simulator/device testing remain blocked by macOS build availability.
- Current AppStore configuration excludes public-source browsing and custom-provider installation/resolution; local CBZ imports, personal Komga servers and optional AniList tracking remain.

## New development branch

See docs/ROADMAP_IMPLEMENTATION.md for reversible edition groups, source migration and local-library recommendations added after this handoff. These changes are in a draft PR, not validated or merged. iCloud remains pending container setup and conflict design. No additional CI run was requested.

## First tasks next session

- [ ] Read this file and docs/KOMIKKU-APPLE-ROADMAP.md, then inspect current main and any new contributor changes.
- [ ] Check macOS runner availability and GitHub Actions startup annotations. Do not repeatedly consume credits while the reported limit remains unresolved.
- [ ] Build/test current main on iPhone and iPad simulators, build Mac Catalyst, and run the AppStore source-boundary/privacy-manifest checks.
- [ ] Resolve compiler/test errors before claiming a passing build.
- [ ] When signing and macOS are available, archive/export an IPA and validate through TestFlight or the intended device-installation route.
- [ ] Preserve existing work and contributor history; do not overwrite concurrent changes.

## Remaining feature list, in suggested order

1. [ ] **Merged library entries** — combine editions/providers into one logical library entry; preserve original chapter ownership, files, reading progress, categories and tracker links. Provide preview and reversible unmerge. Cover merge state in backup/restore tests.
2. [ ] **Source migration** — search an allowed destination provider, preview chapter mappings, skip ambiguous matches, preserve completed progress, and retain the original entry until the user explicitly chooses otherwise. Do not silently equate partial-page positions across different editions.
3. [ ] **Recommendations** — begin with clearly labelled recommendations from the user's existing library. Broader discovery can follow through documented, permitted metadata APIs; no unlicensed bundled catalogs.
4. [ ] **iCloud synchronization** — design identity matching, conflict handling, opt-in controls and migration tests. Explicitly define whether progress, library metadata or files sync. Configure real Apple container identifiers/entitlements and test across two devices; never sync credentials.
5. [ ] **Private categories** — explicit user-facing privacy controls, distinct from concealing functionality from App Review.
6. [ ] **Panoramic/full-cover display** — preserve image aspect ratio and support accessible viewing/sharing of user-authorized covers.
7. [ ] **Update notifications with cover art** — request permission in context; respect best-effort iOS background scheduling.
8. [ ] **Additional tracker integrations** — verify each service's API terms/authentication and test progress conflicts and failures.
9. [ ] **Dedicated macOS experience** — currently Mac Catalyst is the supported desktop target; assess a native macOS target separately.

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
