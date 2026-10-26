# Manga Reader iOS

Native SwiftUI manga reader targeting iOS 17+. Initial source extracted from Handoff.md; it has not been compiled or tested in Xcode.

## Open in Xcode

Quickest: on a Mac run `brew install xcodegen && xcodegen generate && open MangaReader.xcodeproj` (uses `project.yml`; CI in `.github/workflows/build.yml` does the same). Set your team and bundle ID, then build. Manual setup:

1. On a Mac, create a new iOS App named MangaReader using SwiftUI, Swift, and SwiftData; set deployment target to iOS 17.
2. Remove the generated app entry point and sample model/view files.
3. Add App, Domain, Data, and Features to the app target.
4. Add https://github.com/weichsel/ZIPFoundation via Swift Package Manager and link ZIPFoundation to the app target.
5. Select your development team and a unique bundle identifier, then build and address compiler diagnostics.

## Current source

Local CBZ import, library and chapters, paged LTR/RTL reading, zoom, vertical webtoon reading, and reading progress. EPUB and server integrations remain planned. No Xcode project or successful build is included yet.

Known issues include webtoon memory use and approximate jumps, zoom gesture conflicts, first-unread resume behavior, and completion being marked upon opening the last page. Source code is preserved from the handoff with Markdown escapes removed; no functional fixes are claimed.

## Constraints

No bundled scraper lists, adult-content integrations, downloaded executable code, or JavaScriptCore in v1. Planned integrations: user-owned Komga/Kavita/OPDS servers and the official MangaDex API. Review current service terms and App Store requirements before release.

## Licensing

No license has been selected for the original project code. See NOTICE for design references. ZIPFoundation has its own license.

