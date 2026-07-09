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
- [ ] 5 = Keep
- [ ] 3 = Maybe
- [ ] 1 = Reject
- [ ] 0 = Unrated
- [ ] Auto-advance works in preview
- [ ] Next/Previous preview works

## Persistence

- [ ] Close project
- [ ] Reopen project
- [ ] Clip statuses are preserved
- [ ] Metadata is preserved
- [ ] Analysis is preserved
- [ ] Partial ingest state is preserved

## Export

- [ ] CSV export works
- [ ] Copy Keeps to Edit Folder works
- [ ] Export does not overwrite files
