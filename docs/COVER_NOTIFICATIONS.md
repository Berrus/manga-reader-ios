# Full-cover and notification increment

Stacked on the edition-tools branch (PR #11); draft and not validated on Apple platforms.

- Library title → Library tools → View full cover: uncropped, aspect-preserving fit, enlargement, native sharing and JPEG export to Files. Image decoding is downsampled and bounded; no Photos permission is requested.
- Settings → Notifications: explicit notification permission request and opt-in update notices. Titles/covers are off by default. Changing the details preference clears prior notices; disabling removes pending/delivered update notices. Image attachment failures fall back to text.
- One replaceable summary notice is generated after persisted library checks find new chapters. It is best effort, not a guaranteed schedule. No push server or external notification service is added.
- Two regression tests cover title privacy and bounded detailed text. They have not been executed here. Full-cover UI, Files export, share sheets, permission denied/authorized, disable races, cover attachment cleanup and signed device background checks remain required.

CI is skipped while credits are exhausted. No build, IPA, App Store approval or complete roadmap parity is claimed. Private categories, iCloud, additional tracker integrations and dedicated macOS remain pending.
