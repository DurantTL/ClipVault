# ClipVault Roadmap — Next Steps and Future Ideas

Updated: July 9, 2026

## Project Summary

ClipVault is a native macOS video ingest, verification, culling, metadata, and editor handoff app.

The goal is not just to copy files like a transfer utility. The goal is to create a daily project-based video workflow:

    Create Daily Project
    → Choose source card/folder
    → Choose destination
    → Copy and verify files
    → Open the project as a library
    → Preview, cull, rate, tag, analyze, and organize
    → Export selected clips or hand off to an editor

Core tagline: **Copy. Verify. Cull. Organize.**

ClipVault is being designed mainly for Apple Silicon Macs and a Sony a7R V workflow:

- 4K 60p, 4:2:2, 10-bit, non-log footage
- Sony card structure: `PRIVATE/M4ROOT/CLIP`
- Canon/DCF support as a secondary workflow

## Important Safety Rules

These must stay true for every future feature:

1. Never delete source files.
2. Never modify source files.
3. Never write thumbnails or metadata to source cards.
4. Never format SD cards.
5. Never overwrite destination files.
6. Always use safe duplicate naming.
7. Copy first.
8. Verify second.
9. Full playback preview, culling, rating, metadata editing, analysis, aliases, exports, and editor handoff must use copied project files only.
10. New Ingest may show temporary read-only source thumbnails only for identifying sessions/clips before copying.
11. Temporary ingest thumbnails must be stored only in the user cache directory.
12. Library thumbnails must be generated only from copied project files.
13. Partial/canceled ingests must always remain reopenable.
14. Old project JSON files must remain openable.

## Immediate Next Steps

### Step 1 — Verify the latest source picker changes

Manual test checklist:

1. Open ClipVault and click New Ingest.
2. Confirm New Ingest opens as a large standalone window that remembers size/position.
3. Confirm detected source cards appear; click a detected source.
4. Confirm the sandbox permission prompt appears at most once per source.
5. Confirm swapping between sources does not re-prompt for granted sources.
6. Confirm sessions scan and ingest thumbnails appear.
7. Confirm session and individual clip selection work.
8. Choose destination, start a small ingest, cancel halfway.
9. Confirm the partial library opens, copied clips show thumbnails, pending clips do not crash.
10. Resume ingest and confirm the library opens after completion.
11. Preview copied clips, cull with keyboard shortcuts.
12. Close and reopen the project; confirm statuses, metadata, thumbnails, and partial ingest state persist.

### Step 2 — Stabilize before major features

Before adding large new features, make sure this loop is solid:

    Source selection → Session scan → Ingest thumbnails → Select sessions/clips
    → Copy → Verify → Cancel halfway → Open partial library → Resume
    → Library thumbnails → Preview → Cull → Close/reopen

If any part of this is unreliable, fix that before adding more features.

### Step 3 — Merge only when GitHub Actions is green

Do not merge PRs unless the build passes, tests pass, project JSON compatibility tests pass, and a manual ingest test passes for at least a small folder.

### Step 4 — Keep AGENTS.md, README, and TESTING updated

Every major architectural decision should be written into AGENTS.md, README.md, and TESTING.md — especially safety rules, thumbnail rules, source permission behavior, project JSON compatibility, and Apple Silicon performance expectations.

## Near-Term Feature Pass

The next big feature group: **Ratings, Multi-Select, Bulk Metadata, Export, and Editor Handoff.**

This completes the real workflow: Ingest → Verify → Cull → Rate → Tag → Export/Open in editor.

### Feature 1 — Multi-Select Clips

- Command-click: add/remove clip from selection; Shift-click: range select; Command-A: select all visible; Escape: clear.
- Clear selected visual state.
- Batch actions: Mark Keep/Maybe/Reject, clear status, set rating, add/remove tag, assign to custom folder, create aliases, analyze, generate/regenerate thumbnails, copy filenames, reveal in Finder, export selected.

### Feature 2 — 0–5 Star Rating

Keep Keep/Maybe/Reject, add a 0–5 rating with keyboard mapping 0–5 and automatic cull status: 0 → Unrated, 1 → Reject, 2–3 → Maybe, 4–5 → Keep.

### Feature 3 — Bulk Metadata Editing

Batch edit tags, people, location, scene, shot type, notes, flags (Favorite, B-Roll, Sermon, Interview, Social Clip Candidate), custom folder, and manual shot time. Append tags by default; allow replace, clear, and remove-specific.

### Feature 4 — Custom Folders and Aliases

Aliases are lightweight organization; originals remain in `Original Ingest/`. Alias actions for Keep, Maybe, 4–5 stars, tags, and custom folders. Aliases must point to copied project files only; removing aliases never affects originals.

Suggested project structure:

    2026-07-09 Project Name/
      .clipvault-project.json
      .clipvault-cache/ (thumbnails, contact-sheets, analysis)
      Original Ingest/
      Aliases/ (Keep, Maybe, Sermon, B-Roll, Social Media)
      Exports/ (Keep Copies, Keep + Maybe Copies, Clip Reports)

### Feature 5 — Copy Keeps to Edit Folder

Copy (never move) Keeps, 4–5 stars, Keep+Maybe, selected clips, by tag, or by custom folder to a chosen folder. Never overwrite; safe duplicate names; flatten or preserve organization; show progress and an export summary (copied/skipped/failed/total size/destination); reveal folder after completion.

### Feature 6 — CSV / JSON Reports

Clip report, keep list, reject list, metadata JSON, verification report, and analysis report exports with full per-clip fields (filename, status, rating, duration, size, resolution, frame rate, codec, shot time, tags, analysis scores, paths, verification status, and more).

### Feature 7 — Editor Handoff

First version: reveal edit folder, open DaVinci Resolve / Final Cut Pro / Finder at the export folder. Later: FCPXML export, Resolve CSV/EDL/XML-style export, export by rating/status/tag, optional proxy folder.

## Performance and Apple Silicon Roadmap

- Apple Silicon required/strongly recommended; M2 Pro or better for large 4K/10-bit workloads; 16 GB RAM minimum, 32 GB+ for large events; fast SSD; macOS 15+ recommended.
- Use runtime performance profiles (SystemPerformanceProfile: arm64, memory, Metal, tier, recommended concurrency) instead of pretending chip detection is perfect.
- Performance modes: Automatic, Fast, Balanced, Quality.
- BackgroundWorkCoordinator manages ingest copy, verification, thumbnails, contact sheets, analysis, exports, and future cloud transfers.
- Prioritize visible work; cancel background jobs when views close.
- Keep the UI responsive: no main-thread scanning, thumbnailing, or analysis; batch project JSON saves carefully but keep frequent safety saves during ingest.
- Log scan duration, copy speed, verification speed, thumbnails/sec, analysis time, and failure counts.

## AI / Smart Features Roadmap

- **Phase 1 (local rules):** better focus/stability/face-visibility scoring, social-clip candidate scoring, best-frame thumbnails, best-clip suggestions, talking-head detection, stage/worship detection, high-motion detection, lighting warnings.
- **Phase 2 (local Apple frameworks — Vision, Core Image, Core ML, Foundation Models):** suggest tags, scene names, folder names, descriptions, social selects; summarize sessions/projects; detect duplicates; choose best thumbnail frames. Prefer local processing, never upload by default, keep suggestions editable, never auto-identify people by name.
- **Phase 3 (optional cloud, opt-in only):** transcription, summaries, advanced tagging, searchable transcripts, captions. Clear privacy warnings; user chooses which clips to send.

## Cloud Storage Roadmap

- **Phase 1:** treat mounted synced folders (Google Drive, OneDrive, Dropbox, iCloud, Box, Synology, SMB/NAS) as sources/destinations with cloud badges, availability warnings, and post-ingest sync reminders.
- **Phase 2:** cloud-aware workflow — online-only detection, keep-awake helper, backup verification summary.
- **Phase 3:** direct uploads (Drive, OneDrive, Dropbox, Box, B2, Wasabi, S3, WebDAV) with resumable/retryable verified uploads and a local queue.
- **Phase 4:** cloud as a source with verified, resumable downloads — only after local workflows are stable.

## Ingest / Copy UX Direction

Borrow from Hedge/OffShoot: clear Sources/Destinations areas, clickable source cards, storage icons, verification messaging, simple transfer status. But ClipVault is a daily project ingest + culling library, not just a transfer app:

    Hedge/OffShoot: Source → Destination → Transfer
    ClipVault:      Source → Daily Project Library → Cull/Organize/Export

Future New Ingest structure: Left = Sources, Center = Detected Sessions / Transfer Queue, Right = Project Setup + Destinations. Later: backup destination cards, recent destinations, organize settings (rename patterns, folder patterns, ignore rules, tokens).

## Naming Roadmap

Default stays safe: preserve original filenames, flat copy into `Original Ingest/`, never overwrite. Optional future folder structures (by date, session, camera, source) and rename patterns with tokens (project, source, session, original filename, counter, date/shot-time components, camera type).

## Settings Roadmap

Future tabs: General, Sources, Destinations, Organize, Transfers, Reports, Analysis, Performance, Cloud, Advanced — including source auto-detection settings, default destinations, verification mode, report defaults, analysis toggles, performance tuning, cache cleanup, and project repair tools.

## Onboarding Ideas

First-launch intro: set up your drives → copy with protection → organize by project → cull faster → export to edit.

## Testing Strategy

Automated: project/clip Codable round-trips and old-JSON decodes, rating/status mapping, export duplicate naming, thumbnail path resolution, source permission helpers where possible.

Manual: keep a folder of 5–10 short clips for every PR and run the regression checklist in TESTING.md, ending with "confirm no source files were modified."

## Build Discipline

1. Every PR must pass GitHub Actions.
2. Every model/schema change needs Codable compatibility coverage.
3. Every new background task must be cancelable.
4. Every new file operation must respect the safety rules.
5. Anything touching source media must be read-only unless it is copied project media.
6. Every large UI change must be checked against the manual workflow.
7. Do not let feature work break ingest stability.

## Priority Order

1. Stabilize the detected source picker (permissions must not re-prompt) — ✅ shipped
2. Confirm New Ingest window stays large and remembered
3. Confirm ingest source thumbnails work and remain read-only
4. Confirm partial ingest/resume
5. Add 0–5 ratings — ✅ shipped
6. Add multi-select — ✅ shipped
7. Add bulk metadata — ✅ shipped
8. Add Copy Keeps to Edit Folder — ✅ shipped
9. Add CSV/JSON export — ✅ shipped (clip/keep/reject/verification/analysis CSVs + metadata JSON)
10. Add aliases — ✅ shipped (symbolic links in `Aliases/`, copied project media only)
11. Add editor handoff — ✅ shipped (Finder, DaVinci Resolve, Final Cut Pro folder handoff)
12. Add project templates
13. Add better contact sheets
14. Add cloud-synced folder support
15. Add improved local AI analysis
16. Add direct cloud upload later
17. Add optional cloud AI later

## Key Product Direction

ClipVault should be safer than manually dragging files, more project-focused than Hedge, faster for culling than Finder, simpler than full NLE import workflows, local-first and privacy-friendly, optimized for Apple Silicon, and built around real video workflows.

Core identity: **a daily project-based video ingest and culling app for Apple Silicon Macs.**

    Ingest safely. Verify the copy. Cull quickly. Tag and organize. Export the good clips.
