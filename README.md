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
- Optional, off-by-default custom sources (Settings tab) with a Browse tab; see docs/SOURCES.md.
- Resume a partly read chapter before starting an unread one.
- Paged left-to-right/right-to-left and vertical webtoon readers.
- Pinch/double-tap zoom in paged mode, page slider and chapter navigation.
- Per-chapter progress, bounded page indices, fit-specific memory-limited image caching.
- Error messages and retry controls for individual pages that cannot decode.

## Still needs hands-on testing

iPhone/iPad touch behavior, zoom versus page-swipe gestures, orientation changes, VoiceOver, large CBZ files, long webtoon chapters and memory pressure. UI smoke tests do not replace this device pass. Webtoon slider jumps remain approximate with lazy placeholder heights; webtoon pinch zoom and zoom edge chaining are not implemented.

EPUB, server integrations, downloads, categories, trackers, CloudKit and declarative sources remain future work. This is a local-reader MVP, not the complete handoff roadmap.

## Content and licensing

No bundled scraper lists or adult-content integrations. Optional, off-by-default custom sources run sandboxed JavaScript (JavaScriptCore) added by the user; see docs/SOURCES.md, including the App Store risk. Planned sources are user-owned Komga/Kavita/OPDS servers and official MangaDex APIs, subject to current terms and review requirements.

No license has been selected for the original project code. See NOTICE for design references. ZIPFoundation retains its own license. The generated UI-test sample artwork is original and contains no third-party manga.
