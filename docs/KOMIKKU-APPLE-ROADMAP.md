# Komikku-inspired features for Folio Reader

Folio Reader remains a native Swift / SwiftUI application with SwiftData storage, URLSession transport, and UIKit where reader gestures require it. iPhone and iPad are primary targets; Mac Catalyst is built in CI. A dedicated macOS target is a later step.

This is an independent implementation of product ideas. No Komikku source, artwork, branding, extension packages or manga content is included in this change.

## Implemented phases

- Saved source-search chips, isolated by source identifier, persisted on device, removable using their context menu. Maximum 100 searches, 200 characters each. Search definitions currently remain on the device and are not included in metadata backups.
- Library reading-status and offline-availability filters; last-read sorting.
- Multiple-title selection and category assignment, with field restoration on failed saves. Selection follows the current visible results.
- Five accent palettes, a dark cover-derived reader canvas, webtoon autoscroll, preload and memory-cache settings.
- Opt-in saved-query feed (eight queries, three concurrent requests, twenty deduplicated results per query).
- Grouped update history, last-check issues and update progress.
- A separate AppStore scheme restricting providers to personal Komga servers; required-reason privacy declarations and submission notes.

## Feature mapping and later phases

| Komikku capability | Folio Reader status / approach |
| --- | --- |
| Local reading, paged / webtoon, directions | Existing native reader |
| Offline queue, Wi-Fi rules, auto-download | Existing native implementation |
| Categories, history, continue reading, backups | Existing; new bulk categorization and filters |
| Two-way tracker progress | Existing AniList integration; additional services require their API terms and authentication |
| Saved source searches | Implemented in this phase |
| Cover colors, palette selection, panoramic covers | Accent palettes and cover-derived reader background implemented; panoramic cover display remains later |
| Autoscroll, preload and cache controls | Implemented for local/downloaded readers; motion pauses on interaction/backgrounding, respects accessibility |
| Grouped updates, update errors, progress banners | Grouped updates, errors and progress implemented; cover notifications remain later |
| Merged entries and source migration | Later; stable identities, reversible mapping and preview required |
| Feed and recommendations | Saved-query feed implemented; recommendations remain later and require permitted APIs/content |
| Private categories | Later; explicit privacy feature, never a mechanism for concealing app functionality from review |
| iCloud synchronization | Later; entitlements, conflict handling and migration tests required |
| Android APK extensions and extension repos | Not compatible with iOS; no downloaded executable providers |
| Self-installing updates | App Store updates instead |
| Adult-content-specific integrations | Excluded from App Store scope |
| Background refresh schedules | Best effort under iOS scheduling; no guaranteed interval |

## Distribution requirements

Approval is Apple's decision. Swift does not itself confer approval.

1. Ship a complete, useful local-file / personal-server reader. Check permission for every bundled third-party service and catalog. Access to an API does not prove rights to the manga it serves. The AppStore scheme excludes MangaDex and custom-source browsing. The broader development variant still needs an explicit content-rights and service-terms assessment before any App Store submission.
2. Keep executable behavior in the submitted binary. Do not import Android extensions or introduce downloadable scripts. Declarative JSON source configuration remains data-only in the development build and is unavailable in the AppStore variant.
3. Support user-owned or licensed imports and personal media servers. A personal server is not a substitute for having content rights.
4. Provide a privacy policy, accurate privacy disclosures and age rating, working support links, licensed screenshots/sample comics, demo access and clear review notes describing all source configuration.
5. Complete physical iPhone/iPad testing, VoiceOver and Dynamic Type checks, IPv6-only networking and real-world large-library testing.
6. Review signing, bundle identifier, tracker client configuration, API terms and third-party notices before submission. Use StoreKit if paid digital features are added, subject to the applicable storefront rules.

References checked 2026-10-26:
- https://github.com/komikku-app/komikku (README feature inventory)
- https://github.com/komikku-app/komikku/blob/master/LICENSE (Apache-2.0 at repository root; individual files and dependencies may have separate notices)
- https://developer.apple.com/app-store/review/guidelines/ (especially 2.5.2, 2.5.4, 2.5.19, 5.2.1 and 5.2.2)

If Komikku code is reused in a future phase, inspect each file and dependency license, preserve required license/copyright/NOTICE material, and mark modifications as required. Its software license does not grant content or trademark rights.
