# Native macOS target — assessment

**Status: not built.** Folio Reader runs on the Mac today as a Mac Catalyst app (the `MangaReader` target with `SUPPORTS_MACCATALYST`). This note records what a native AppKit/SwiftUI-for-macOS target would take, so it can be decided with facts.

## Why it was not built here

A second target can only be verified by compiling it on a Mac, and a broken target in `project.yml` would stop `xcodegen generate` — and every CI job — for the whole project. It was left out rather than added unverified.

## What the code looks like (measured on 2026-10-27)

- 79 Swift files in the app; **17 use UIKit types** directly.
- Heaviest UIKit use: `Features/Reader/ZoomableImage.swift` and `ScrollAutoAdvance.swift` (`UIScrollView` zoom, `CADisplayLink` autoscroll), `App/DemoLibrary.swift` (test data), `ReaderView`/`ReaderViewModel` (`UIImage`, `UIScreen`), `Data/ImageDownsampler.swift` and `LibraryImporter.swift` (`UIImage` encode/decode), `Downloads/*` (`UIApplication` background tasks), `AppIconPicker`, and the AniList/MyAnimeList sign-in screens (`UIWindowScene` anchors).
- iOS-only frameworks: `BackgroundTasks` (update refresh), `UIApplication.setAlternateIconName`, `UIApplicationDelegate` (background URL sessions).
- Already portable: `Domain/*`, `Sources/*` (Komga, Suwayomi, OPDS, MangaDex, JSON sources), `Tracking/*` networking, `Data/Backup*`, `EPUBArchive`, `CBZArchive`, `SourceTransport`, most SwiftUI screens. `LocalAuthentication`, `AuthenticationServices` and `UserNotifications` exist on macOS.

## What a port needs

1. A `macOS` application target in `project.yml` sharing the portable folders, with `UIKit` files excluded or wrapped in `#if canImport(UIKit)`.
2. A small platform layer: `typealias PlatformImage = UIImage / NSImage`, image decode/encode helpers (`ImageIO` already works on both), and a Mac zoom/scroll view (`NSScrollView` with `allowsMagnification`) replacing `ZoomScrollView`.
3. Replace `ScrollAutoAdvance` (`CADisplayLink`) with a timer-driven `NSScrollView` offset, or drop autoscroll on the Mac.
4. No-ops or Mac equivalents for background refresh (`NSBackgroundActivityScheduler`), alternate icons (not supported), and `handleEventsForBackgroundURLSession`.
5. macOS app sandbox entitlements (user-selected files, network client) and a macOS app icon set.
6. A macOS CI job and UI tests (the iOS UI tests do not transfer).

Rough size: a few days of work plus Mac-side debugging, mostly in the reader.

## A much smaller step to consider first

Keep Catalyst but switch from "Scaled to Match iPad" to **Optimize Interface for Mac** (Xcode: target > General > Mac Catalyst, or include device family 6 in `TARGETED_DEVICE_FAMILY`). Controls then look native, and nothing in the code changes. It needs a visual check of every screen on a Mac.

## Recommendation

Stay on Mac Catalyst for now. Revisit a native target only if Catalyst's limits (reader scrolling, window behaviour, menu bar) become a real problem for Mac users.
