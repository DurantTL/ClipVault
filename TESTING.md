# SlateBox Manual Test Checklist

Use a small test folder with 5–10 short video clips before testing real SD cards.

## Automated coverage

The following mechanics are covered by unit tests in `ClipVaultTests/` and run in CI, so the manual checklist can focus on real-media and permission behavior:

- Streaming copy: byte-identical copies, chunked progress, cancel leaving a resumable partial, resume from a partial, stale-partial discard, never overwriting a destination (`StreamingCopyServiceTests`).
- Verification: fast size check and strong SHA256 pass/fail behavior (`VerificationServiceTests`).
- Source scanning: Sony `PRIVATE/M4ROOT/CLIP` prioritization, proxy exclusion/opt-in, Canon `DCIM` detection, sidecar filtering, recursive generic scans (`SourceScannerTests`).
- Export: copy-only exports, safe `_1`/`_2` duplicate naming, missing-source skips (`ClipExportServiceTests`, `RatingAndSuggestionTests`).
- Project/clip JSON compatibility and rating/status mapping (`ProjectCodableTests`, `ClipCodableTests`, `RatingAndSuggestionTests`).
- Preflight media check: already-imported, same-name-different-size, backup/recent-project, and possible-duplicate classification (`PreflightMediaCheckTests`).
- Physical sorting: folder moves with safe `_1` naming, undo restoring path and folder assignment, and failure leaving clip metadata untouched (`FileMoveServiceTests`).
- Ingest orchestration: end-to-end copy + verify on temp folders, per-clip failure isolation, correct incomplete state, safe names for colliding flat filenames, and cancel leaving a reopenable project with sources untouched (`IngestServiceTests`).
- Recovery helpers: destination-capacity decisions plus actionable disk-full, permission-loss, and unavailable-volume messages (`IngestServiceTests`).
- Diagnostics report content (`DiagnosticsReportServiceTests`).

Still manual only (needs real media, hardware, or relaunch): thumbnail generation from real video, mid-copy pause/resume timing, security-scoped bookmark persistence across relaunch, removable-volume detection, and backup destinations end-to-end.

## Build

- [ ] `make icons` works
- [ ] Xcode opens the project
- [ ] App builds
- [ ] App launches

## Ingest

- [ ] New Ingest opens without clipping
- [ ] Source folder can be selected
- [ ] Sony card structure is detected
- [ ] Canon/DCF `DCIM` folder is detected
- [ ] A detected non-removable source prompts for access at most once
- [ ] Swapping between two granted sources does not re-prompt
- [ ] Swapping back to the first source rescans without a prompt
- [ ] After relaunch, a previously granted non-removable source does not show the picker again
- [ ] Sessions are shown
- [ ] Session selection works
- [ ] Individual clip selection works, if available
- [ ] Destination can be selected
- [ ] Reported destination free space is shown
- [ ] Start Ingest is blocked when known free space is smaller than the selected media
- [ ] A destination whose capacity cannot be read shows an advisory but remains usable
- [ ] Project folder name works
- [ ] Start Ingest enables only when ready

## Partial Ingest

- [ ] Start ingest
- [ ] Cancel after 1–2 files
- [ ] Partial library opens
- [ ] Copied clips appear
- [ ] Pending clips do not crash
- [ ] Resume Ingest works
- [ ] Failed clips are retried by Resume Ingest
- [ ] Canceling a resumed ingest leaves the project labeled Canceled and resumable
- [ ] Disconnecting the destination mid-copy shows a reconnect/resume message and preserves the partial project
- [ ] Filling the destination mid-copy shows an out-of-space/resume message
- [ ] Revoking source or destination access shows a grant-access/resume message

## Library

- [ ] Grid is the main workspace
- [ ] Inspector is not too wide
- [ ] Inspector can be hidden/shown
- [ ] Spacebar preview works
- [ ] 5 = 5★ Keep/Favorite
- [ ] 4 = 4★ Keep
- [ ] 3 = 3★ Maybe
- [ ] 2 = 2★ Maybe-Low
- [ ] 1 = 1★ Reject
- [ ] 0 = Unrated
- [ ] Stars on cards and inspector set the rating
- [ ] Setting cull status keeps a consistent rating (Keep does not downgrade 5★)
- [ ] Auto-advance works in preview
- [ ] Next/Previous preview works

## Multi-Select and Batch

- [ ] Command-click adds/removes clips from selection
- [ ] Shift-click selects a range
- [ ] Command-A selects all visible clips
- [ ] Escape clears the multi-selection
- [ ] Selection bar shows the selected count
- [ ] Batch status/rating applies to all selected clips
- [ ] Batch Add Tag / Remove Tag work
- [ ] Batch Edit Metadata sheet applies tags, fields, and flags
- [ ] Apply Suggested Ratings only changes unrated clips

## Persistence

- [ ] Close project
- [ ] Reopen project
- [ ] Clip statuses are preserved
- [ ] Metadata is preserved
- [ ] Analysis is preserved
- [ ] Disconnecting the project drive before a metadata edit shows a project-save error banner
- [ ] Reconnect the project drive and use Retry Project Save; the banner clears only after the save succeeds
- [ ] Partial ingest state is preserved

## Export

- [ ] Copy Keeps to Edit Folder copies the right clips
- [ ] Copy Keep + Maybe / 4–5 Star / Selected variants work
- [ ] Export shows progress and a summary, then reveals the folder
- [ ] Export does not overwrite files (duplicates get `_1`, `_2`)
- [ ] Exporting with no matching clips shows an explanation instead of doing nothing
- [ ] Clip Report / Keep List / Reject List CSVs export
- [ ] Verification and Analysis report CSVs export
- [ ] Source files are untouched after export
