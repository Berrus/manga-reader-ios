# App Store submission preparation

This file is a release checklist and draft review note, not evidence of Apple approval. Do not submit until the owner-dependent items are complete.

## App Store configuration

Select the generated FolioReader-AppStore scheme to build/archive the AppStore configuration. This compile-time variant exposes local-file imports, personal Komga servers, and opt-in installation of declarative JSON sources and repositories. Built-in public MangaDex browsing remains unavailable. Existing entries from unavailable providers show a source-unavailable message. The standard MangaReader Debug/Release configurations retain their current features for development and other distribution; do not submit that variant without a separate rights and terms review.

The differences are documented openly; there is no remote switch to turn excluded providers back on. App Store review notes should describe the submitted variant accurately. Source code for the broader development configuration is not a promise that every feature is in the submitted app.

## Architecture and code

- Native Swift / SwiftUI. Public UIKit APIs for reader zoom/scrolling.
- No downloaded executable providers, Android APKs, or self-updater.
- Source JSON is declarative configuration. Explain its complete behavior to review; permission to access every service is still required.
- PrivacyInfo.xcprivacy declares own-app UserDefaults (CA92.1) and file metadata in the app container / user-selected documents (C617.1 / 3B52.1). Generate Xcode's privacy report and audit the final archive plus ZIPFoundation before submission. These entries do not replace App Store privacy disclosures.
- Tracking in the privacy manifest means advertising/cross-app tracking, not AniList reading-progress synchronization. No advertising SDK is included.

## Required owner decisions

- Replace com.example.FolioReader with the registered identifier; select the signing team and distribution provisioning.
- Configure an approved AniList API client. Confirm its service terms and redirect setup.
- Confirm permission for any public content service or bundled catalog. Review the existing MangaDex integration separately. An API being public is not a content license.
- Publish a real privacy-policy URL and support URL under the owner's control. Determine disclosures for requests made to third-party sources and AniList.
- Use only owned/licensed sample comics, covers and screenshots.
- Complete the age-rating questionnaire accurately. No adult-content-specific integrations are included.
- No app-specific accounts or purchases are introduced here. Reassess account deletion and StoreKit rules if either is added.

## Draft review notes

Folio Reader imports user-selected CBZ files from Files and connects to media servers configured by the user. It includes local/downloaded paged and webtoon reading, categories, source-specific saved searches, an opt-in saved-search feed, reading history, offline queue controls, and optional AniList progress synchronization. The submitted AppStore variant supports personal Komga servers and opt-in declarative JSON source installation; built-in MangaDex browsing is excluded at compile time.

Provide a licensed demo library and credentials for any service reviewers need. List all enabled public/custom source behavior and its authorization. Explain that source definitions contain endpoint/field data only; they do not download or run code. Do not conceal source controls or enable different functionality after review.

Background refresh is best effort under iOS scheduling. Webtoon autoscroll stops when the reader loses foreground activity or the user scrolls, and is disabled with VoiceOver or Reduce Motion.

## Release validation still required

- Physical iPhone and iPad: import, navigation, gestures, rotation, Split View, offline relaunch, cancellation and low storage.
- VoiceOver, Dynamic Type, Reduce Motion, contrast and keyboard navigation.
- IPv6-only network and denied local-network permission.
- Large archives/libraries and memory pressure.
- A signed Release archive, privacy report, dependency notices and TestFlight validation. Simulator CI cannot establish App Store acceptance.

References:
- https://developer.apple.com/app-store/review/guidelines/
- https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype
- https://developer.apple.com/documentation/bundleresources/privacy-manifest-files
