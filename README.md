# Folio Reader

A native SwiftUI CBZ reader for iPhone, iPad and Mac (Catalyst), targeting iOS 17+. The initial source has passed a macOS CI simulator build. This update adds unit tests, simulator UI smoke tests, and actual screenshot artifacts. Check the latest Actions run for their current outcome; a successful build alone does not establish runtime quality.

## Build and run in Xcode

The app is named **Folio Reader** (home-screen name and bundle ID). The Xcode target, scheme and Swift module keep the internal name `MangaReader`, so tests and CI commands below still use that.

You need a Mac. The Xcode project is generated from `project.yml` (the `.xcodeproj` and `Info.plist` are git-ignored), so always regenerate rather than editing project settings by hand.

**Requirements:** macOS with Xcode 16 or newer (iOS 17 SDK or later), [Homebrew](https://brew.sh), and an Apple ID signed in under Xcode > Settings > Accounts. The Swift package ZIPFoundation is fetched automatically on first build.

1. Clone and generate the project:

   ```sh
   git clone https://github.com/Berrus/manga-reader-ios.git
   cd manga-reader-ios
   brew install xcodegen
   xcodegen generate
   open MangaReader.xcodeproj
   ```

2. Wait for Xcode to resolve packages (status bar, top). If it stalls, use File > Packages > Reset Package Caches.
3. Pick the **MangaReader** scheme and an iPhone or iPad simulator, then press **Run** (Cmd-R). Tests: Cmd-U.
4. Re-run `xcodegen generate` whenever `project.yml` changes or you add/remove source files.

Set your signing details once in `project.yml` so they survive regeneration:

```yaml
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.yourname.FolioReader   # must be unique to you
        DEVELOPMENT_TEAM: ABCDE12345                          # your Team ID (developer.apple.com > Membership)
```

Then run `xcodegen generate` again. (Alternatively, set the team in Xcode under the MangaReader target > Signing & Capabilities, but that is lost when the project is regenerated.)

## Install on your iPhone or iPad

1. Connect the device with a cable (or pair it wirelessly), unlock it and tap **Trust**.
2. On the device turn on **Settings > Privacy & Security > Developer Mode** and restart when asked (iOS 16+).
3. In Xcode choose your device as the run destination and press Run. The first time, Xcode registers the device and creates a development profile.
4. If iOS says the developer is untrusted, go to **Settings > General > VPN & Device Management**, select your Apple ID and tap **Trust**.

What your Apple account allows:

| Account | Result |
| --- | --- |
| Free Apple ID | Installs on your own devices; the app stops opening after **7 days** and must be re-run from Xcode (max 3 apps at once). |
| Apple Developer Program ($99/year) | Builds last a year; you can use **TestFlight** to share builds and submit to the App Store (Product > Archive > Distribute App). |

Common problems: "No profiles / signing for team" means the team or bundle ID is not set (or the ID is taken: change it); "Developer Mode required" means step 2 was skipped; a stale SwiftData store after a model change is fixed by deleting the app from the device or simulator and running again.

## AniList tracking (optional)

1. Sign in at <https://anilist.co/settings/developer> and create a client. Set the **Redirect URL** to `folioreader://anilist`.
2. Copy the client ID into `project.yml` (`ANILIST_CLIENT_ID`), then run `xcodegen generate`.
3. In the app: Settings > Tracking > Connect AniList. Open a series and tap **Link to AniList**.

Progress is synced when you finish a chapter and at launch. The higher chapter number wins and sync never marks local chapters unread. AniList stores whole chapters only, so 12.5 is sent as 12. Chapter numbers come from file names, so check them if a sync looks off. The token is kept in the Keychain; no client secret is used.

## MyAnimeList tracking (optional)

1. Create an API client at <https://myanimelist.net/apiconfig> (app type "other") and set the **App Redirect URL** to `folioreader://mal`.
2. Put the client ID in `project.yml` (`MAL_CLIENT_ID`), then run `xcodegen generate`.
3. Settings > Tracking > Connect MyAnimeList, then open a series and tap **Link to MyAnimeList**. A series can be linked to AniList and MyAnimeList at the same time.

Sign-in uses PKCE, so no client secret is stored; tokens are refreshed automatically and kept in the Keychain. MyAnimeList stores whole chapters (12.5 is sent as 12), its search needs at least 3 letters, and it hides adult titles by default.

## Private categories

Settings > Library > Categories: swipe a category right to make it private. Its series are hidden from the library, history, updates and suggestions until you unlock with Face ID, Touch ID or the device passcode (the lock button in the library toolbar). The app locks again when it leaves the foreground, and notifications never show a private series' title or cover. It needs a device passcode. This is a privacy convenience, not encryption: private series are still stored on the device and included in backups.

## Run on a Mac

The Mac version is built with Mac Catalyst. Choose the **My Mac (Mac Catalyst)** destination and Run. It needs a signing team (the app is sandboxed with user-selected file access and network client entitlements). Arrow keys, space and up/down turn pages.

## Platforms

iPhone, iPad (all orientations, multitasking) and Mac (Catalyst). Layout adapts to window size: the library grid adds columns, the webtoon reader caps page width, and images are sized from the real reader viewport.

## Automated verification

The Build and Test workflow selects an installed iPhone simulator, runs MangaReaderTests and MangaReaderUITests, and uploads simulator-screenshots and test-results artifacts. It runs for main pushes and pull requests and can also be started manually in Actions.

Unit coverage includes chapter sorting and resume selection, progress bounds and completion, CBZ ordering and filtering, invalid archives, real file import and append, failed import cleanup, image decoding, and cache separation between paged/webtoon modes.

UI smoke tests import original generated sample CBZs into a temporary in-memory library, open the paged and webtoon readers, exercise the page slider, and capture library/reader/empty-state screenshots. Sample seeding is compiled only in DEBUG and requires the UI_TESTING launch environment variable. Normal launches never seed sample content.

## Current features

- Local CBZ/ZIP import with explicit CBZ file-type registration.
- Library with cover cards, a Continue reading shelf, title search, sorting (recent, title, unread), an unread filter, progress bars, chapter lists and manual read/unread.
- Series page with a cover header, progress and chapter status indicators.
- Four app icons (Indigo default, Ink, Coral, Light) chosen in Settings on iPhone and iPad; sources are in `design/`.
- Categories (library chips, long-press to move), History tab, reader settings (background, edge-tap page turning, keep screen on).
- Browse: MangaDex via its official API (safe/suggestive content only), your own Komga servers (Settings > Library > Servers, passwords in the Keychain), and optional custom sources.
- Offline downloads: add a series from Browse to the library, then download chapters (swipe a chapter, or the download menu on the series page). Settings > Library > Downloads sets automatic downloads: series you're reading, selected series, or recently updated; how many chapters to keep ahead; Wi-Fi only; delete after reading. Updates are checked when you open the app (at most every 4 hours), with a best-effort iOS background refresh.
- Backup and restore of categories, progress and tracker links (Settings > Backup).
- Suwayomi servers you run yourself (Settings > Library > Servers): browse sources, search, add to library, read and download. See docs/SUWAYOMI.md.
- Optional, off-by-default custom sources (Settings tab) with a Browse tab; see docs/SOURCES.md.
- Resume a partly read chapter before starting an unread one.
- Paged left-to-right/right-to-left and vertical webtoon readers.
- Pinch/double-tap zoom in paged and webtoon modes, page slider and chapter navigation.
- Per-chapter progress, bounded page indices, fit-specific memory-limited image caching.
- Error messages and retry controls for individual pages that cannot decode.

## Still needs hands-on testing

iPhone/iPad touch behavior, zoom versus page-swipe gestures, orientation changes, VoiceOver, large CBZ files, long webtoon chapters and memory pressure. UI smoke tests do not replace this device pass. Webtoon slider jumps remain approximate with lazy placeholder heights; webtoon pinch zoom (1x to 3x, double-tap to reset) is new and untested on a device, and zoom edge chaining in paged mode is not implemented.

The full feature checklist, including everything not implemented, is in [docs/FEATURE_STATUS.md](docs/FEATURE_STATUS.md).

Not built yet (from the handoff): a text EPUB reader (comic EPUBs work), Kavita's REST API (its OPDS feed works), a native macOS target (see docs/MACOS_NATIVE.md), widget and Shortcuts, localization catalogs, and the monthly source-update pipeline. iCloud sync, background downloads, OPDS, EPUB, Kitsu and MangaDex recommendations exist as code and need real devices, servers and accounts to verify. Custom sources use the declarative JSON endpoint format described in docs/SOURCES.md; older script definitions must be replaced.

## Content and licensing

No bundled scraper lists or adult-content integrations. Optional custom sources use declarative JSON endpoint definitions. Downloaded programs are not executed; see docs/SOURCES.md. Planned sources are user-owned Komga/Kavita/OPDS servers and official MangaDex APIs, subject to current terms and review requirements.

No license has been selected for the original project code. See NOTICE for design references. ZIPFoundation retains its own license. The generated UI-test sample artwork is original and contains no third-party manga.

## Reliability and safety checks

The CI matrix runs the full unit/UI suite on iPhone and iPad simulators and builds Mac Catalyst.
Source requests and image redirects share a host policy and streaming byte cap; CBZ page extraction and decoded bitmap sizes are bounded.
Backups match stable identities first, with explicit reporting when duplicate titles make a fallback ambiguous.
The download queue is persisted, reattached to saved chapter records after relaunch, paused when connectivity policy changes, and acknowledged before chapter deletion.
Resizing the reader invalidates its decoded images. Next/Previous chapter navigation streams chapters that are not downloaded.
Check the current Actions results rather than relying on earlier screenshot runs.
