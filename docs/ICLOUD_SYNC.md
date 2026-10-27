# iCloud sync

Optional sync of **library metadata** between your own devices through iCloud Drive. It is off by default and does nothing until it is enabled in the app *and* the build has the iCloud entitlement.

## What syncs

Categories (including which are private), reading progress, reader settings per series and tracker links. **Not** synced: comic files, downloads, passwords, sign-in tokens, and deletions.

## How it works

- Every device writes one file to iCloud Drive, `Documents/FolioReader/backup-<device id>.json`, using the same format as Settings > Backup.
- Every device merges the files other devices wrote, using the same restore as a backup: series are matched by title and chapters by name, and progress and "read" marks only move **forward**. A category made private on one device stays private.
- Because no two devices write the same file, there are no write conflicts to resolve, and merging the same file twice changes nothing.
- It syncs when the app opens (at most every 15 minutes) and from Settings > Library > iCloud sync > Sync now.

Limits: a series is identified by its title, so renaming it on one device makes it look new on the other; unread marks and deletions don't propagate; a series must already exist on the device (import its files first) for its progress to apply.

## Turning it on in a build

Apple's iCloud capability needs a paid Apple Developer account, so it is **not** enabled in the default project (a free account can't sign it). To enable it:

1. In your developer account, register an iCloud container, e.g. `iCloud.com.yourname.FolioReader`, and add it to your App ID.
2. In `project.yml`, under the `MangaReader` target `entitlements.properties`, add:

   ```yaml
   com.apple.developer.icloud-container-identifiers: [iCloud.com.yourname.FolioReader]
   com.apple.developer.icloud-services: [CloudDocuments]
   com.apple.developer.ubiquity-container-identifiers: [iCloud.com.yourname.FolioReader]
   ```

3. Run `xcodegen generate`, build with your signing team, and turn on Settings > Library > iCloud sync on two devices signed into the same iCloud account.

Without the entitlement the screen says iCloud isn't available and no files are written.

## Why not CloudKit or SwiftData's iCloud mode

SwiftData's CloudKit store does not support unique constraints, which the library models use for their ids, and it would change how the whole library is stored. A file-per-device merge keeps the existing store untouched and cannot damage it.

## Not verified

This has not been run on two real devices. Test with a throwaway library first: sync, then change progress on each device and sync again.
