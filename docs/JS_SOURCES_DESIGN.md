# Design note: optional JavaScript sources (not built)

Status: proposal for approval. Nothing here is implemented.

## Goal

Let users add sources whose logic is a small JavaScript package (Paperback-style), so
site scrapers can exist without a server and without a new app release. Keiyoushi's Kotlin/APK
extensions stay out of scope: they cannot run on iOS (see docs/SUWAYOMI.md for the supported route).

## Where it fits today

- `JSSource` is a *declarative* JSON adapter. Scripts are never evaluated, and old script
  manifests are kept on disk but disabled (`JSSourceManifest.script`). This design adds a
  second, separate kind rather than reviving that field.
- `SourceRegistry`, `SourceAccessPolicy`/`SourceTransport` (host allow-list, redirect checks,
  size caps) and the repository/replacement-warning flow in `SourceStore` already exist and are reused.

## Distribution rule

New compile-time flag in `DistributionPolicy`:

```swift
static var allowsScriptedSources: Bool   // false when APP_STORE is defined
```

- Off in the `FolioReader-AppStore` configuration: the JavaScript engine glue is not even
  compiled in (`#if !APP_STORE`), so the App Store binary contains no script execution path.
- On in normal, sideload and TestFlight builds.
- Whether to ever enable it for the App Store is a separate decision for the owner after reading
  Apple's current guideline 2.5.2 and the developer agreement; this design does not assume it.
- No bundled packages or repository URLs, matching the handoff. The user types the address.

## Runtime

- `JavaScriptCore` (system framework, no dependency), one fresh `JSContext` per call, discarded after.
- The script gets **no** DOM, timers, `eval` of fetched text, file system, Keychain, cookies or app data.
- Only host functions we inject:
  - `http.get(url, headers) -> {status, body}` — routed through `SourceTransport`, so the declared
    `hosts` allow-list, HTTPS-only rule, redirect checks and size caps apply. Text bodies only.
  - `html.select(body, cssSelector) -> [{text, attr}]` — a small parser on our side, since there
    is no DOM. Needs a parser (SwiftSoup would be a new dependency; a minimal selector subset is the
    lazy alternative, decided during implementation).
  - `log(message)` — capped.
- Limits: wall-clock timeout per call (~15 s, enforced by running on a background queue and
  abandoning the context), max script size 256 KB, max response 10 MB, max returned items 500.
- Script contract mirrors the existing `Source` protocol: `search(query, page)`, `details(id)`,
  `chapters(id)`, `pages(chapterId)`; each returns plain JSON that is decoded into the existing
  `MangaSummary`/`ChapterSummary`/`PageSource` types and validated like declarative output.
  Page image URLs are checked against the declared hosts.

## Package and repository format

```json
{"id":"example.js","name":"Example","version":"3","hosts":["example.com"],
 "entry":"https://example.com/sources/example.js","sha256":"<hex>"}
```

- Repositories are JSON catalogs of such entries (same 20 repos / 1 MB / 200 entries limits as today).
- The script is fetched over HTTPS and its SHA-256 must match the catalog entry, so a script
  cannot change silently after the user approved it. A new hash means a new version and a new
  confirmation (reusing the replacement warning, which already compares domains and origin).
- Install screen shows name, version, allowed domains and states plainly that it runs third-party code.
- Stored as data under Application Support; ids prefixed `js.` in `SourceRegistry`.
- Paperback/Aidoku packages are not directly compatible; a script must be written against our contract.

## Settings and safety UX

- Off by default; a separate switch from declarative sources, with a warning and optional Face ID gate.
- Per-source disable and remove; removing deletes the script.
- Errors from a script are shown as source errors, never crash the app (context is isolated).

## Work breakdown

1. `allowsScriptedSources` flag and `#if !APP_STORE` guard; a test that the App Store build
   has no path to the engine (extends the existing source-boundary checks).
2. `ScriptedSource: Source` + JavaScriptCore host bindings + timeout.
3. Package/repository decoding, hash check, install and replacement UI.
4. Registry wiring (`js.` ids), settings switch.
5. Tests: contract decoding, host allow-list enforcement from script, timeout, size caps, hash mismatch,
   flag off in App Store config.
6. Docs: docs/SOURCES.md, FEATURE_STATUS.md.

## Risks / unknowns

- Third-party scripts are untrusted code. The sandbox limits what they can reach, but
  correctness of the host-function boundary needs a careful review and real-device testing.
- Scraping specific sites can raise copyright and terms-of-service issues for whoever publishes
  the packages; Folio ships none.
- No iOS build or test is possible in this session environment; verification would be via the
  GitHub Actions workflow once you authorize a run.
- Keiyoushi's catalogue does not carry over: each source would need to be rewritten in JavaScript.
