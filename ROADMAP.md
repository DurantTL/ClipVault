# SlateBox Roadmap — Path to a Final Product

Updated: July 20, 2026

## Project Summary

SlateBox is a native macOS video ingest, verification, culling, metadata, and editor handoff app.

The goal is not just to copy files like a transfer utility. The goal is a daily project-based video workflow:

    Create Daily Project
    → Choose source card/folder
    → Choose destination
    → Copy and verify files
    → Open the project as a library
    → Preview, cull, rate, tag, analyze, and organize
    → Export selected clips or hand off to an editor

Core tagline: **Ingest. Verify. Cull. Hand off.**

SlateBox is designed mainly for Apple Silicon Macs and a Sony a7R V workflow:

- 4K 60p, 4:2:2, 10-bit, non-log footage
- Sony card structure: `PRIVATE/M4ROOT/CLIP`
- Canon/DCF support as a secondary workflow

### Naming note

The product may be renamed again ("SlateBox" appears taken on App Store Connect). All user-visible brand strings flow through `AppBrand.swift`, so a rename is a one-file change plus the checklist documented in that file. The hidden on-disk identifiers (`.clipvault-project.json`, `.clipvault-cache`, `.clipvault-partial`, `~/Library/Caches/ClipVault/`) are **permanent format identifiers** and never change with the product name.

The App Store listing does not have to use only the short base brand. A distinctive brand can be paired with a concise functional phrase—for example, `<Brand>: Video Ingest`—while the app keeps the shorter brand in its logo and interface. See [`NAMING.md`](NAMING.md) for limits, candidate patterns, subtitle ideas, and the final decision process.

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

## Shipped

- Detected source picker with stable permission grants (no re-prompt for granted sources).
- Guided ingest: session scan, Sony `PRIVATE/M4ROOT/CLIP` + Canon `DCIM` + generic detection, proxy exclusion/opt-in, individual clip selection.
- Streaming chunked copy with `.clipvault-partial` temp files, pause/resume/cancel, and reopenable partial ingests.
- Fast size and Strong SHA256 verification; primary + Backup 1 + Backup 2 destinations.
- 0–5 star ratings synced with Keep/Maybe/Reject; multi-select; batch actions and bulk metadata.
- Copy Keeps to Edit Folder; CSV reports (clip/keep/reject/verification/analysis) + project metadata JSON.
- Aliases (symbolic links to copied project media only); editor folder handoff for Finder, DaVinci Resolve, Final Cut Pro.
- Camera/card metadata on ingest; local rule-based + Vision analysis with suggested ratings (never auto-applied).
- Apple Silicon performance profiles and background work coordination; bounded thumbnail memory cache and preview prewarming.
- Brand-agnostic string handling via `AppBrand.swift`; automated safety-pipeline tests (copy, verify, scan, export naming) in CI.
- Preflight Media Check / already-imported detection: source clips are compared by file identity (filename, size, modified date, duration) against the destination, configured backups, and recent projects, with clip-level statuses (New, Already at Destination, Already in Project, Already on Backup, Possible Duplicate, Same Name Different Size) and skip-already-copied selection.

## Phase 1 — Trustworthiness (in progress)

Make the existing core loop provably reliable before adding surface area.

- ✅ Brand-agnosticism pass: user-visible strings flow through `AppBrand.appName`; on-disk names frozen and documented.
- ✅ No dead controls: settings toggles without an implementation (contact sheets, Finder tags export, XMP sidecar export, post-ingest analysis, technical details) are hidden until their features exist. Keys remain reserved.
- ✅ Automated tests for the safety-critical pipeline: `StreamingCopyServiceTests`, `VerificationServiceTests`, `SourceScannerTests`, `ClipExportServiceTests` run in CI alongside the Codable/rating/alias tests.
- ✅ Recovery implementation pass: known insufficient destination space blocks ingest; low/unknown capacity is explained; disk-full, disconnect, permission, and read-only failures have actionable messages; canceled/failed projects retain correct resumable state; project-save/export failures are visible instead of discarded.
- Hardware recovery validation remains: physically disconnect an SSD and NAS mid-copy, revoke folder access, restore each resource, and complete the resume checklist in `TESTING.md` before calling the recovery audit finished.
- Decompose `LibraryViewModel` (~1,000 lines) into focused pieces (selection, filtering/sorting, thumbnails, export, analysis) before the next feature pass.
- Continue the regression loop in TESTING.md for every PR:

      Source selection → Session scan → Ingest thumbnails → Select sessions/clips
      → Copy → Verify → Cancel halfway → Open partial library → Resume
      → Library thumbnails → Preview → Cull → Close/reopen

## Phase 2 — Distribution (make it a product)

- **Final name decision** — blocked on App Store Connect availability. Test a distinctive base brand alone and in full-name variations such as `<Brand>: Video Ingest`, then choose a complementary subtitle. Follow the strategy and checklist in [`NAMING.md`](NAMING.md); the code rename remains a one-file change plus the `AppBrand.swift` checklist.
- **Real brand asset**: replace the generated placeholder icon and SwiftUI logo with final artwork; commit real icon assets. Do this together with the name decision.
- ✅ **Developer ID signing + notarization, DMG packaging, release workflow** — shipped as `.github/workflows/release.yml`: push a `vX.Y.Z` tag → Release build + tests → optional signing/notarization (activates automatically once the Apple secrets are configured in repo settings) → DMG → GitHub Release. Unsigned DMGs publish for testing until the secrets exist.
- ✅ **Versioning + changelog** — `CHANGELOG.md` added; the release workflow stamps `MARKETING_VERSION` from the tag and the build number from the CI run.
- **Updates**: manual download checks against GitHub Releases first (keeps the app Apple-frameworks-only); Sparkle only if auto-update becomes a real need. Mac App Store build optional later (sandboxing is already in place).
- ✅ **First-launch onboarding** — five-step walkthrough on first launch, re-openable via Help → Welcome; plus Help → Keyboard Shortcuts cheat sheet.
- ✅ **Save Diagnostics** — Help → Save Diagnostics Report… writes a local plain-text report (app, system profile, settings, recent projects). Local-first; no telemetry.

## Phase 3 — Workflow-completing features (priority order)

1. **MHL (Media Hash List) checksum reports** — industry-standard proof-of-transfer (Hedge/Silverstack parity). Builds on the existing SHA256 code; big credibility win for paid production work.
2. **Contact sheets / filmstrip hover-scrub** — settings key and background-work plumbing already exist; implement generation from copied media only, then re-enable the hidden toggle.
3. **Finder tags + XMP sidecar export** — implement the writers behind the reserved `finderTagsExport` / `xmpSidecarExport` keys, then re-enable the hidden toggles. Sidecars only; never write into MP4/MOV media.
4. **FCPXML / Resolve-friendly handoff** — carry ratings, tags, and notes into the NLE (FCPXML keywords/ratings; Resolve CSV/EDL-style metadata) instead of folder-open only.
5. **Project templates** and ingest rename/folder-pattern tokens (project, source, session, original filename, counter, date/shot-time components, camera type). Defaults stay safe: preserve original filenames, flat copy, never overwrite.

## Performance and Apple Silicon

Shipped baseline: bounded in-memory thumbnail cache and adjacent-preview prewarming. Continue to measure time-to-first-thumbnail and time-to-first-preview before adding heavier processing.

- Runtime performance profiles (arm64, memory, Metal, tier, recommended concurrency); modes Automatic, Fast, Balanced, Quality.
- `BackgroundWorkCoordinator` manages ingest copy, verification, thumbnails, analysis, exports, and future contact sheets/cloud transfers; every background task must be cancelable.
- No main-thread scanning, thumbnailing, or analysis; frequent safety saves during ingest.
- Log scan duration, copy speed, verification speed, thumbnails/sec, analysis time, and failure counts.

## AI / Smart Features (after Phase 3)

- **Phase A (local rules):** better focus/stability/face-visibility scoring, social-clip candidate scoring, best-frame thumbnails, talking-head detection, high-motion detection, lighting warnings.
- **Phase B (local Apple frameworks — Vision, Core Image, Core ML, Foundation Models):** suggest tags, scene names, folder names, descriptions, social selects; summarize sessions/projects; duplicate detection; best thumbnail frames. Local processing, never upload by default, suggestions always editable, never auto-identify people by name. `FoundationModelSuggestionService` stays a guarded placeholder until a real integration lands.
- **Phase C (optional cloud, opt-in only):** transcription, summaries, advanced tagging, captions. Clear privacy warnings; the user chooses which clips to send.

## Cloud Storage (after Phase 3)

- **Phase A:** treat mounted synced folders (Google Drive, OneDrive, Dropbox, iCloud, Box, Synology, SMB/NAS) as sources/destinations with cloud badges, availability warnings, and post-ingest sync reminders.
- **Phase B:** cloud-aware workflow — online-only detection, keep-awake helper, backup verification summary.
- **Phase C:** direct uploads (Drive, OneDrive, Dropbox, Box, B2, Wasabi, S3, WebDAV) with resumable, verified uploads and a local queue.
- **Phase D:** cloud as a source with verified, resumable downloads — only after local workflows are stable.

## Settings Direction

Future tabs: General, Sources, Destinations, Organize, Transfers, Reports, Analysis, Performance, Cloud, Advanced — source auto-detection settings, default destinations, verification mode, report defaults, analysis toggles, performance tuning, cache cleanup, and project repair tools. Rule: a control only ships when its feature works.

## Testing Strategy

Automated (in CI): project/clip Codable round-trips and old-JSON decodes, rating/status mapping, streaming copy (identical bytes, cancel/resume, partial handling, never overwrite), verification (size + SHA256), source scanning (Sony/Canon/generic, proxy and sidecar rules), export duplicate naming, alias safety.

Manual: keep a folder of 5–10 short clips for every PR and run the regression checklist in TESTING.md, ending with "confirm no source files were modified."

## Build Discipline

1. Every PR must pass GitHub Actions (build + tests).
2. Every model/schema change needs Codable compatibility coverage.
3. Every new background task must be cancelable.
4. Every new file operation must respect the safety rules.
5. Anything touching source media must be read-only unless it is copied project media.
6. Every large UI change must be checked against the manual workflow.
7. Do not let feature work break ingest stability.
8. No settings control ships before its feature is implemented.

## Key Product Direction

SlateBox should be safer than manually dragging files, more project-focused than Hedge, faster for culling than Finder, simpler than full NLE import workflows, local-first and privacy-friendly, optimized for Apple Silicon, and built around real video workflows.

Core identity: **a daily project-based video ingest and culling app for Apple Silicon Macs.**

    Ingest safely. Verify the copy. Cull quickly. Tag and organize. Export the good clips.
