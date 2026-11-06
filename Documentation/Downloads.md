# Direct-file download subset

The Android Flow download pipeline was inspected at upstream commit
3f3e2a6101fe511003f8b694876fe8c6ece89c66, particularly DownloadStreamResolver,
DownloadRequest and DownloadStreamPolicy. It resolves fresh streams, downloads separate tracks,
remuxes media and stores captions/tags. The current iOS implementation is a new native subset,
not a translation or substitute for that full pipeline.

Supported source: a direct muxed MP4 or AAC/MP4 audio URL already available in the native player.
HLS, separate audio/video tracks, range-limited URLs, untransformed signature/n URLs and foreign
hosts are rejected. No second extraction call is made. The Download menu is explicit and asks
the user to download only content they are allowed to keep. No downloads run during development.

A single foreground transfer uses URLSession's download API. HTTP status, MIME type and expected
versus actual length are checked. Files above 1 GB are rejected after transfer; this is a retained
file limit, not a bandwidth cap. AVFoundation checks playability and audio/video tracks before
committing the file. Cancellation discards temporary files where execution can be interrupted.
If cancellation arrives after the atomic commit, the completed file remains and is shown as saved.

Storage uses UUID-derived filenames, a versioned metadata index and an operation journal written
before every add/delete mutation. No signed URLs are persisted. Staging paths are deterministic
from the record ID. Startup reconciles complete interrupted adds, restores deletes whose index
change did not commit, and finishes cleanup for committed deletes. Incomplete or contradictory
files are preserved and reported; no guessed cleanup is performed. Failed immediate rollback
or restoration is surfaced and its journal remains for recovery. Invalid indexes are preserved.
This covers process interruption; filesystem/power-loss durability is not claimed.

Every URLSession redirect is policy-checked before following. The final URL is checked again,
including the range prohibition. Manager mutations and record publication are serialized.
Cancellation is honored before the commit job begins. Once its synchronous journaled transaction
starts, it deliberately completes or rolls back; a late Cancel must not interrupt index/media
consistency. Portable tests cover pre-commit cancellation and explicit interrupted transaction
phases. Actual iOS cancellation during URLSession/AVFoundation/commit remains unverified.

The downloads screen supports local playback and confirmed deletion. Files live in app storage
and may be included in device backups. Foreground transfer progress is indeterminate. Keep the
app open. Background/resumable transfers, format merging, fresh-URL retries, subtitles, cover
art, tagging, playlists/queues and offline watch-history integration are not yet implemented.

Portable storage tests use fixture bytes, not playable media. They verify policy, persistence,
rollback, symlink rejection and corruption preservation. AVFoundation/SwiftUI integration and
real-media downloads still require Xcode/device verification, unavailable in this environment.

## Recovery refinements

An interrupted add with an incomplete staged file and no index entry is moved to deterministic
Recovery storage together with a copy of its operation journal. It is not published as playable,
and the pending journal is cleared so other downloads can proceed. Recovery evidence is not
automatically deleted. The app reports the number of preserved interrupted transfers. A later
cleanup/export interface for recovery files is not implemented yet.

Delete journals record whether the original media file existed. If a previously missing file
was being removed and the app terminated before the index write, startup can safely finish that
metadata-only deletion. Unknown/contradictory states still preserve files and report an error.
Spool copying and media validation share cleanup handling, including failed partial copies.
