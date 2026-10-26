# Komikku-inspired features for Folio Reader

Folio Reader remains a native Swift / SwiftUI application with SwiftData storage, URLSession transport, and UIKit where reader gestures require it. iPhone and iPad are primary targets; Mac Catalyst is built in CI. A dedicated macOS target is a later step.

This is an independent implementation of product ideas. No Komikku source, artwork, branding, extension packages or manga content is included in this change.

## Implemented in this phase

- Saved source-search chips, isolated by source identifier, persisted on device, removable using their context menu. Maximum 100 searches, 200 characters each. Search results are not backed up.
- Library reading-status and offline-availability filters; last-read sorting.
- Multiple-title selection and category assignment, with field restoration on failed saves. Selection follows the current visible results.

## Feature mapping and next phases

| Komikku capability | Folio Reader status / approach |
| --- | --- |
| Local reading, paged / webtoon, directions | Existing native reader |
| Offline queue, Wi-Fi rules, auto-download | Existing native implementation |
| Categories, history, continue reading, backups | Existing; new bulk categorization and filters |
| Two-way tracker progress | Existing AniList integration; additional services require their API terms and authentication |
| Saved source searches | Implemented in this phase |
| Cover colors, palette selection, panoramic covers | Next visual phase; native image analysis and SwiftUI |
| Autoscroll, preload and cache controls | Next reader phase; cancel on backgrounding and respect accessibility |
| Grouped updates, update errors, progress banners | Next library phase |
| Merged entries and source migration | Later; stable identities, reversible mapping and preview required |
| Feed and recommendations | Later; only documented APIs and permitted content |
| Private categories | Later; explicit privacy feature, never a mechanism for concealing app functionality from review |
| iCloud synchronization | Later; entitlements, conflict handling and migration tests required |
| Android APK extensions and extension repos | Not compatible with iOS; no downloaded executable providers |
| Self-installing updates | App Store updates instead |
| Adult-content-specific integrations | Excluded from App Store scope |
| Background refresh schedules | Best effort under iOS scheduling; no guaranteed interval |

## Distribution requirements

Approval is Apple's decision. Swift does not itself confer approval.

1. Ship a complete, useful local-file / personal-server reader. Check permission for every bundled third-party service and catalog. Access to an API does not prove rights to the manga it serves. The existing MangaDex integration still needs an explicit content-rights and service-terms assessment before an App Store submission.
2. Keep executable behavior in the submitted binary. Do not import Android extensions or introduce downloadable scripts. Existing declarative JSON source configuration is data-only, but Apple may still assess its scope and the content it enables; it is not automatically approved.
3. Support user-owned or licensed imports and personal media servers. A personal server is not a substitute for having content rights.
4. Provide a privacy policy, accurate privacy disclosures and age rating, working support links, licensed screenshots/sample comics, demo access and clear review notes describing all source configuration.
5. Complete physical iPhone/iPad testing, VoiceOver and Dynamic Type checks, IPv6-only networking and real-world large-library testing.
6. Review signing, bundle identifier, tracker client configuration, API terms and third-party notices before submission. Use StoreKit if paid digital features are added, subject to the applicable storefront rules.

References checked 2026-10-26:
- https://github.com/komikku-app/komikku (README feature inventory)
- https://github.com/komikku-app/komikku/blob/master/LICENSE (Apache-2.0 at repository root; individual files and dependencies may have separate notices)
- https://developer.apple.com/app-store/review/guidelines/ (especially 2.5.2, 2.5.4, 2.5.19, 5.2.1 and 5.2.2)

If Komikku code is reused in a future phase, inspect each file and dependency license, preserve required license/copyright/NOTICE material, and mark modifications as required. Its software license does not grant content or trademark rights.
