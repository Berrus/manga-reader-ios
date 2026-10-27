# Komikku backup import

Folio accepts Komikku `.tachibk` backups from Settings → Backup → Restore. The importer reads the gzip-wrapped Protocol Buffers library section, then applies progress and categories to existing Folio entries only when title and chapter matches are unambiguous. Progress only moves forward through the existing restore service.

It does not install Android extensions, copy comic files, restore source credentials/preferences, or import tracker account state. A backup can contain more library series than Folio currently has; unmatched entries are reported and skipped. Keep the original backup unchanged.

The decoder limits compressed input to 10 MB and expanded data to 64 MB, rejects malformed protobuf, and does not write the selected backup to disk. Tests use synthetic sample data and must not include a user's real backup.

When validating a real backup on macOS, confirm the preview counts before restoring and verify category/progress matches for a few known entries. The attached sample used during implementation must never be committed or copied into the repository.
