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
| **Recommendations** | 🟠 Partial | Folio suggests titles **already in your library**. Remote recommendations depend on source support. |
| **Merge editions and migrate sources** | 🟠 Code present | Merge/unmerge and migration with a mapping preview are present. Behaviour on Apple platforms needs verification. |
| **Backup and restore** | 🟢 Implemented | Folio backup/restore and Komikku backup import. Compatibility with a specific real backup still needs testing. |
| **Tracking** | 🟠 Code present; needs real accounts | AniList, MyAnimeList (PKCE sign-in, token refresh) and Kitsu (email/password exchanged for tokens), all with forward-only sync. AniList and MyAnimeList need a client ID. None has been tried against a real account. |
| **Suwayomi** | 🟠 Code present; needs testing | Server saving, source browsing, search, reading, downloads and library support. Open [PR #19](https://github.com/Berrus/manga-reader-ios/pull/19) carries this work (open and mergeable; its simulator checks passed except the App Store UI test, fixed on the branch but not re-run). The GraphQL calls have not been run against a real server. See [SUWAYOMI.md](SUWAYOMI.md). |
| **Paperback repositories/extensions** | 🔴 Not compatible | Folio uses its own declarative JSON source repositories ([SOURCES.md](SOURCES.md)). Paperback extensions are not compatible. |
| **Paperback 0.9 extension repositories** | 🟠 Built for non-App-Store builds; untested on device | Add a repository base address, install extensions, browse and read. Compatibility layer covers search/details/chapters/pages only; see [SOURCES.md](SOURCES.md). |
| **Keiyoushi Android extensions** | 🟠 Indirect route; needs a real server | APK extensions cannot run in a Swift app. Instead the app can add the repository to a Suwayomi server and install extensions there (Browse > server > Extensions; not in the App Store build). See [SUWAYOMI.md](SUWAYOMI.md). |
| **iCloud sync** | 🟠 Code present; off by default | Opt-in sync of categories, progress and tracker links through iCloud Drive (one file per device, forward-only merge, no write conflicts). Needs the iCloud entitlement and a paid developer account, so it is not enabled in the default build, and it has not been run on two devices. See [ICLOUD_SYNC.md](ICLOUD_SYNC.md). |
| **Full-cover display** | 🟠 Code present; verify | A full-cover view with sharing exists. Its current UI and sharing behaviour need checking. |
| **Webtoon pinch zoom** | 🟠 Code present; needs device testing | Pinch from 1x to 3x with sideways scrolling, and double-tap to zoom or reset. Zoomed pages use the normal-resolution bitmap, so they are a little soft above 2x. Zoom edge-chaining is covered in the next row. |
| **Paged-mode zoom edge-chaining** | 🟠 Code present; needs device testing | Pulling a zoomed page past its left or right edge turns the page (direction follows right-to-left reading). |
| **EPUB** | 🟠 Partial | Comic EPUBs (image-based books, read in spine order) import and read like CBZ files. Reflowable text EPUBs are rejected; there is no text reader. |
| **Kavita and OPDS** | 🟠 Code present; needs a real server | OPDS catalog client with page streaming ([OPDS.md](OPDS.md)); Kavita works through its OPDS URL. Kavita's REST API is not implemented. |
| **Background downloads** | 🟠 Code present; off by default | "Keep downloading when the app is closed" hands pages to a background URL session; chapters complete the next time the app opens. Needs device testing. |
| **Native macOS target** | 🔴 Not built | Mac Catalyst is the desktop target. See the assessment in [MACOS_NATIVE.md](MACOS_NATIVE.md). |

## Not implemented (checklist)

- [ ] Reflowable (text) EPUB reader, and Kavita's native REST API (OPDS works).
- [ ] Higher-resolution decoding for zoomed webtoon pages.
- [ ] Recommendations from additional sources.
- [ ] Broader cover-based theming of entries and the reader.
- [ ] Native macOS target (assessed, see [MACOS_NATIVE.md](MACOS_NATIVE.md)).
- [ ] Widget and Shortcuts actions; localization catalogs.
- [ ] The monthly source-update pipeline and remote kill switch for sources.
- [ ] Release work: registered bundle ID and signing team, IPA/TestFlight, privacy policy and support URLs, final privacy disclosures, owned sample content, physical-device checks. See [APP_STORE_SUBMISSION.md](APP_STORE_SUBMISSION.md) and [NEXT_SESSION.md](NEXT_SESSION.md).

## Needs verification, not new code

- [ ] iCloud sync on two real devices with the entitlement enabled.
- [ ] Comic EPUB import with real files from several publishers.
- [ ] OPDS against a real Kavita (and Komga) server.
- [ ] Kitsu sign-in and sync with a real account.
- [ ] Background downloads: start a large chapter, close the app, reopen.
- [ ] Zoom edge-chaining and webtoon pinch zoom on a real device.
- [ ] Real-server run of the Suwayomi flow (connection, sources, search, chapters, pages) and its chapter ordering.
- [ ] Merge/unmerge and source migration on a real library.
- [ ] Komikku backup import with a real `.tachibk` file.
- [ ] Private categories: unlock, lock-on-background and the passcode-required message on a real device.
- [ ] Webtoon pinch zoom with autoscroll and chapter switching on a real device.
- [ ] MyAnimeList sign-in, token refresh and a real sync (needs a client ID and a test account).
- [ ] Alternate app icons on a device (the registration test passes on the simulator).
- [ ] Background refresh and downloads on a physical device.
