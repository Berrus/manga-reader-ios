# Roadmap implementation progress

## Added in this branch

- Reversible merged library entries using an optional SwiftData group ID. Source IDs, chapters, chapter file paths, categories, reading state and tracker links remain on their original models. Existing groups expand in the preview; unmerge removes only the group IDs.
- Library grid groups editions after filtering, so a matching edition remains discoverable. Open the group to choose an edition; edition-level actions affect that edition only. Counts/sorting are based on the representative matching edition, not an aggregate across providers.
- Source migration with allowed-provider selection, explicit search and mapping preview. Creates a new edition and retains the original. Matches unique exact chapter name/number pairs, then unique positive chapter numbers. Completed status is copied; partial-page positions and downloaded files stay with the original. Category, reader preferences and tracker links are copied to the new edition.
- Recommendations from the existing library only, using categories/title words and unfinished reading; no external recommendation API or user-data transfer.
- Backup version 3 includes edition group IDs; versions 1/2 remain readable. Groups restore only when all their saved editions resolve unambiguously.
- Ten XCTest regression cases cover grouping/unmerge, ownership, save-failure cleanup, existing groups, migration ambiguity/source checks, partial-progress preservation, recommendations and backup compatibility.

## How to find the features

Open a library title → Library tools → Merge editions, Migrate source, or Library suggestions. Merged library cards open an edition chooser with an Unmerge action.

## Validation and release limits

This environment is Linux without Swift/Xcode. No iOS build, simulator tests, SwiftData migration run, IPA or device validation has been performed for this branch. Regression tests are written but NOT executed. Do not treat the last verified 71-test/device reader build as validation of this new branch.

The new optional SwiftData property needs an existing-store upgrade test on Apple platforms. Include a failure-injected import, repeated merge/unmerge, backup restore, active-download ownership and VoiceOver checks before merging.

Commit messages use [skip ci] to avoid spending the exhausted Actions allowance. The draft PR is for code review and later Apple-platform validation. Existing AppStore source boundaries are retained by using SourceRegistry's allowed providers, rather than introducing downloadable code or new catalogs.

## iCloud synchronization

Built as an opt-in file-per-device merge through iCloud Drive (see docs/ICLOUD_SYNC.md): categories, progress and tracker links, forward-only, no comic files, passwords or tokens. It is off by default and needs the iCloud entitlement, which is not in the default project.

Still open for iCloud:
1. Register an iCloud container for the real bundle identifier and add an optional signed iCloud build configuration without breaking local-only builds.
2. Identity: this first version matches series by title and chapters by name, as backups do. Stable cross-device identities for remote entries (personal-server ids differ between devices) are not done.
3. Conflict and reset semantics beyond "progress only moves forward"; deletions do not propagate.
4. Tests for concurrent updates, reset, duplicate identities, cancellation and malformed files.
5. Validation on two signed devices with the same iCloud account, including offline changes, account switching and opt-out.

Apple references:
- https://developer.apple.com/documentation/foundation/filemanager/url(forubiquitycontaineridentifier:)
- https://developer.apple.com/documentation/foundation/nsfilecoordinator

Other roadmap items (private categories, full-cover display, update notifications, MyAnimeList and Kitsu) are built; see docs/FEATURE_STATUS.md for what each still needs in the real world. The dedicated macOS target is assessed, not built (docs/MACOS_NATIVE.md).
