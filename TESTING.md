# ClipVault Manual Test Checklist

Use a small test folder with 5–10 short video clips before testing real SD cards.

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
- [ ] Project folder name works
- [ ] Start Ingest enables only when ready

## Partial Ingest

- [ ] Start ingest
- [ ] Cancel after 1–2 files
- [ ] Partial library opens
- [ ] Copied clips appear
- [ ] Pending clips do not crash
- [ ] Resume Ingest works
- [ ] Retry Failed works

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
