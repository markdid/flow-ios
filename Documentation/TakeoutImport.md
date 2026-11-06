# Local Google Takeout CSV import

Implemented 2026-11-06 from `data/local/YouTubeTakeoutCsvParser.kt` at upstream commit 3f3e2a6101fe511003f8b694876fe8c6ece89c66. The native library has an Import Google Takeout CSV entry. This is a subset of Android Takeout import, not a full archive restore.

Supported files:
- Extracted subscription CSV: channel ID, matching YouTube channel URL, channel title.
- Extracted playlist-video CSV: video ID and optional offset date/time. Creates a new local playlist in file order; user supplies/edits its name.

Header recognition follows upstream’s row shapes rather than English column names, so localized headers work. A header and valid first data row are required. Later invalid or duplicate rows are counted in preview and skipped. Quoting/UTF-8 errors or whole-file limits reject the entire file; no partial writes happen while parsing. CSV supports BOM, quoted commas/escaped quotes, CRLF and multiline quoted fields. Control characters or multiline channel names are rejected as invalid rows, matching upstream name validation. IDs/URL hosts/path equality, timestamps/calendar dates and nonempty bounded names are validated. Playlist files do not contain titles; existing metadata is preserved and new videos display their IDs. Original timestamp values are validated but not restored.

Limits: 10 MB, 10,000 nonblank data rows, 32 columns and 16,000 Unicode scalars per field. Channel names additionally use upstream’s 1,000 UTF-16-unit/control-character limit. Oversized files are rejected, not silently truncated. Unsupported/empty files are reported rather than interpreted as an empty restore.

The local file picker obtains security-scoped access. The UI rejects symlinks/nonregular files and reads bounded chunks with a byte cap, including files that grow after the size preflight. A preview shows counts and up to 20 entries. Nothing is uploaded, resolved online or executed; CSV strings are text, not formulas. The user must explicitly press Import/Create playlist. Subscription import uses the existing merge operation, preserving dates/music/notification settings. Playlist import adds missing video metadata and one new playlist in a single repository commit; duplicate target IDs, built-in targets, mismatched orders or failed writes leave memory unchanged. Reimport creates another playlist and is disclosed.

Not supported: ZIP, Takeout history (HTML/JSON), music-library CSV, playlist metadata/name matching across files, multi-file imports, backups/restores, original per-video timestamps or upstream’s full malformed-row recovery policy. No real user export was read or modified during implementation; all tests use synthetic fixtures.

Ten portable tests cover CSV syntax, localization, shape recognition, invalid rows, date/URL validation, size/row/field/column caps, dedup/order, metadata preservation, persisted reopen and failed-write atomicity and cancellation before parsing. SwiftUI file-provider behavior, preview/navigation lifecycle and Apple compilation remain unverified. In particular, leaving during parsing cancels retained preparation/reader tasks and invalidates the result; byte reads and parser loops cooperatively check cancellation. Already-issued file-provider reads can finish before the next cancellation check; an explicit commit already requested by the user is allowed to complete.
