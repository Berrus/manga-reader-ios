# Feature status

Where Folio Reader stands against its roadmap and Komikku-style features. Last checked against the code on 2026-10-27. Simulator tests (iPhone, iPad, Mac Catalyst build) passed on that date; "needs device testing" means it has not been tried on real hardware or a real server.

Legend: 🟢 implemented · 🟠 partial or needs verification · 🔴 not implemented / not compatible

| Feature | Status | What is available or missing |
|---|---|---|
| **Library and reading progress** | 🟢 Implemented | Cover grid, search, sorting, unread filter, progress and continue reading. |
| **Reader modes** | 🟢 Implemented | Left-to-right, right-to-left and vertical webtoon; paged zoom and chapter navigation. |
| **Categories** | 🟢 Implemented | Categories and bulk category assignment. |
| **Hidden/private categories** | 🟠 Code present; needs device testing | Swipe a category to make it private; its series are hidden from the library, history, updates and suggestions until unlocked with Face ID, Touch ID or the passcode. Locks when the app leaves the foreground; notifications never show private titles or covers. A privacy convenience, not encryption. |
| **Downloads** | 🟢 Implemented | Offline chapters, queue, Wi-Fi rules and automatic download options. Actual background behaviour needs device testing. |
| **Updates and history** | 🟢 Implemented | Reading history, grouped updates, update progress and errors. iOS background refresh is best effort. |
| **Themes** | 🟠 Partial | Accent palettes and a cover-derived **reader background** exist. Komikku's broader cover-based entry and reader theming is not established as equivalent. |
| **Autoscroll and cache settings** | 🟢 Implemented | Webtoon autoscroll, preload and memory-cache controls. |
| **Saved searches and feed** | 🟠 Partial | Saved searches and a feed based on saved queries exist. This is not necessarily the same as Komikku's source-wide feed. |
| **Recommendations** | 🟠 Partial | Folio suggests titles **already in your library**. Source-provided related titles and recommendations are not implemented. |
| **Merge editions and migrate sources** | 🟠 Code present | Merge/unmerge and migration with a mapping preview are present. Behaviour on Apple platforms needs verification. |
| **Backup and restore** | 🟢 Implemented | Folio backup/restore and Komikku backup import. Compatibility with a specific real backup still needs testing. |
| **Tracking** | 🟠 Partial | AniList and MyAnimeList (PKCE sign-in, token refresh, forward-only sync). Both need a client ID and a real-account test. Kitsu is outstanding. |
| **Suwayomi** | 🟠 Code present; needs testing | Server saving, source browsing, search, reading, downloads and library support. Open [PR #19](https://github.com/Berrus/manga-reader-ios/pull/19) carries this work (open and mergeable; its simulator checks passed except the App Store UI test, fixed on the branch but not re-run). The GraphQL calls have not been run against a real server. See [SUWAYOMI.md](SUWAYOMI.md). |
| **Paperback repositories/extensions** | 🔴 Not compatible | Folio uses its own declarative JSON source repositories ([SOURCES.md](SOURCES.md)). Paperback extensions are not compatible. |
| **Keiyoushi Android extensions** | 🔴 Not directly compatible | Android APK extensions cannot run in a Swift app. A Suwayomi server may provide an indirect route, subject to testing and the server's installed sources. |
| **iCloud sync** | 🔴 Not implemented | Needs a defined sync scope, Apple configuration (container, entitlements) and conflict handling. Credentials must never sync. |
| **Full-cover display** | 🟠 Code present; verify | A full-cover view with sharing exists. Its current UI and sharing behaviour need checking. |
| **Webtoon pinch zoom** | 🟠 Code present; needs device testing | Pinch from 1x to 3x with sideways scrolling, and double-tap to zoom or reset. Zoomed pages use the normal-resolution bitmap, so they are a little soft above 2x. Zoom edge-chaining in paged mode is still missing. |

## Not implemented (checklist)

Everything above marked 🔴, plus items from the original handoff and release plan:

- [ ] Zoom edge-chaining in paged mode, and higher-resolution decoding for zoomed webtoon pages.
- [ ] iCloud/CloudKit sync (scope, identity matching, conflict handling, two-device tests).
- [ ] Kitsu tracker (check the service's API terms and authentication).
- [ ] Source-provided recommendations and related titles.
- [ ] Broader cover-based theming of entries and the reader.
- [ ] EPUB support (needs the Readium toolkit).
- [ ] Kavita and OPDS clients.
- [ ] True background downloads (URLSession background sessions); today downloads run while the app is active plus iOS's short grace period.
- [ ] Widget and Shortcuts actions; localization catalogs.
- [ ] Native macOS target (Mac Catalyst is the supported desktop target today).
- [ ] The monthly source-update pipeline and remote kill switch for sources.
- [ ] Release work: registered bundle ID and signing team, IPA/TestFlight, privacy policy and support URLs, final privacy disclosures, owned sample content, physical-device checks. See [APP_STORE_SUBMISSION.md](APP_STORE_SUBMISSION.md) and [NEXT_SESSION.md](NEXT_SESSION.md).

## Needs verification, not new code

- [ ] Real-server run of the Suwayomi flow (connection, sources, search, chapters, pages) and its chapter ordering.
- [ ] Merge/unmerge and source migration on a real library.
- [ ] Komikku backup import with a real `.tachibk` file.
- [ ] Private categories: unlock, lock-on-background and the passcode-required message on a real device.
- [ ] Webtoon pinch zoom with autoscroll and chapter switching on a real device.
- [ ] MyAnimeList sign-in, token refresh and a real sync (needs a client ID and a test account).
- [ ] Alternate app icons on a device (the registration test passes on the simulator).
- [ ] Background refresh and downloads on a physical device.
