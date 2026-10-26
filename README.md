# Manga Reader iOS

A native SwiftUI CBZ reader for iPhone and iPad, targeting iOS 17+. The initial source has passed a macOS CI simulator build. This update adds unit tests, simulator UI smoke tests, and actual screenshot artifacts. Check the latest Actions run for their current outcome; a successful build alone does not establish runtime quality.

## Open in Xcode

On a Mac with Xcode installed:

```sh
brew install xcodegen
xcodegen generate
open MangaReader.xcodeproj
```

Choose your development team and replace the placeholder bundle ID before installing on your own device. The generated project and Info.plist are intentionally ignored; project.yml is their source of truth.

## Automated verification

The Build and Test workflow selects an installed iPhone simulator, runs MangaReaderTests and MangaReaderUITests, and uploads simulator-screenshots and test-results artifacts. It runs for main pushes and pull requests and can also be started manually in Actions.

Unit coverage includes chapter sorting and resume selection, progress bounds and completion, CBZ ordering and filtering, invalid archives, real file import and append, failed import cleanup, image decoding, and cache separation between paged/webtoon modes.

UI smoke tests import original generated sample CBZs into a temporary in-memory library, open the paged and webtoon readers, exercise the page slider, and capture library/reader/empty-state screenshots. Sample seeding is compiled only in DEBUG and requires the UI_TESTING launch environment variable. Normal launches never seed sample content.

## Current features

- Local CBZ/ZIP import with explicit CBZ file-type registration.
- Library grid, title search, unread badges, chapter lists and manual read/unread.
- Resume a partly read chapter before starting an unread one.
- Paged left-to-right/right-to-left and vertical webtoon readers.
- Pinch/double-tap zoom in paged mode, page slider and chapter navigation.
- Per-chapter progress, bounded page indices, fit-specific memory-limited image caching.
- Error messages and retry controls for individual pages that cannot decode.

## Still needs hands-on testing

iPhone/iPad touch behavior, zoom versus page-swipe gestures, orientation changes, VoiceOver, large CBZ files, long webtoon chapters and memory pressure. UI smoke tests do not replace this device pass. Webtoon slider jumps remain approximate with lazy placeholder heights; webtoon pinch zoom and zoom edge chaining are not implemented.

EPUB, server integrations, downloads, categories, trackers, CloudKit and declarative sources remain future work. This is a local-reader MVP, not the complete handoff roadmap.

## Content and licensing

No bundled scraper lists, adult-content integrations, downloaded executable code or JavaScriptCore in v1. Planned sources are user-owned Komga/Kavita/OPDS servers and official MangaDex APIs, subject to current terms and review requirements.

No license has been selected for the original project code. See NOTICE for design references. ZIPFoundation retains its own license. The generated UI-test sample artwork is original and contains no third-party manga.
