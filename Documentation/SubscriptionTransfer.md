# NewPipe subscription transfer

Adapted from Flow Android Client data/backup/NewPipeSubscriptionCodec.kt at
3f3e2a6101fe511003f8b694876fe8c6ece89c66, modified 2026-11-06.

Supported: YouTube service 0 and canonical UC channel IDs, deduplicated import preview,
atomic merge, and NewPipe-compatible JSON export keys. Missing service_id defaults to 0,
as in upstream. Existing subscription dates/music/notification preferences are preserved.

Handles and /user/ or /c/ legacy URLs are reported separately and not imported. They require a
real channel-resolution implementation, not a guessed UC identifier. Non-YouTube services,
invalid hosts, credential-bearing URLs and invalid identifiers are not imported. No file upload
or network channel resolution occurs. Import and export share limits of 10 MB and 10,000 entries. Oversized exports fail explicitly; they are not truncated. Structurally malformed entries (for example, a numeric name) reject the entire import file before any library change. Unsupported URLs/services in otherwise valid entries are counted and skipped.

The user chooses the file and explicitly confirms the supported entries after preview. Export
uses the system file exporter so the user chooses its destination. This is not a full app backup,
watch-history migration, or Android Flow backup compatibility. The six portable subscription-transfer tests pass in the Linux Swift 6.0.3 package suite
(see Verification.md). The file UI remains uncompiled and untested on iOS.
