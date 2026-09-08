# SlateBox Roadmap — Path to a Final Product

Updated: September 8, 2026

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
- `GitHubUpdateCheckService` (Help → Check for Updates…) and `DiagnosticsReportService` (Help → Save Diagnostics Report…).
- `MHLReportService` — written and unit-tested, but **not yet reachable from the UI** (#67). It is not a shipped user-facing feature until it has an entry point.
- Preflight Media Check / already-imported detection: source clips are compared by file identity (filename, size, modified date, duration) against the destination, configured backups, and recent projects, with clip-level statuses (New, Already at Destination, Already in Project, Already on Backup, Possible Duplicate, Same Name Different Size) and skip-already-copied selection.

## Phase 1 — Trustworthiness (in progress)

Make the existing core loop provably reliable before adding surface area.

- ✅ Brand-agnosticism pass: user-visible strings flow through `AppBrand.appName`; on-disk names frozen and documented.
- ✅ No dead controls: settings toggles without an implementation (contact sheets, Finder tags export, XMP sidecar export, post-ingest analysis, technical details) are hidden until their features exist. Keys remain reserved.
- ✅ Automated tests for the safety-critical pipeline: `StreamingCopyServiceTests`, `VerificationServiceTests`, `SourceScannerTests`, `ClipExportServiceTests` run in CI alongside the Codable/rating/alias tests.
- ✅ Recovery implementation pass: known insufficient destination space blocks ingest; low/unknown capacity is explained; disk-full, disconnect, permission, and read-only failures have actionable messages; canceled/failed projects retain correct resumable state; project-save/export failures are visible instead of discarded.
- ✅ Decompose `LibraryViewModel` into focused pieces (selection, filtering/sorting, thumbnails, export, analysis) — #52.
- Hardware recovery validation remains: physically disconnect an SSD and NAS mid-copy, revoke folder access, restore each resource, and complete the resume checklist in `TESTING.md` before calling the recovery audit finished (#55).

### The three remaining trust gates

No paid trust claim ships until these are done. They are the prerequisites for the safe-release wedge, the proof artifacts, and archive re-verification.

1. **Destination-path containment and project-name validation** (#90) — every write must be provably inside the destination the user selected. Enforced at a single validation entry point, tested against traversal and separator injection, and applied to primary, backups, exports, aliases, reports, and cache.
2. **Independent primary/backup destination state** (#91) — per-clip, per-destination copy and verification records. A backup failure must never obscure a verified primary copy, and a verified primary must never imply a verified backup. This is the data model that "safe to remove" and "clear to format" are computed from.
3. **Full-content verification default** (#92) — the shipping default is a size check, which cannot detect corruption that preserves length. Hash the source once during the copy (hash-on-read) so full-content verification does not cost a second card pass, then make it the default. "Verified" in the UI, reports, and MHL output must mean full-content verification.

### Regression loop

Continue running this in TESTING.md for every PR:

    Source selection → Session scan → Ingest thumbnails → Select sessions/clips
    → Copy → Verify → Cancel halfway → Open partial library → Resume
    → Library thumbnails → Preview → Cull → Close/reopen

Remaining Phase 1 code-quality items: harden `Clip` Codable (#54), `LibraryViewModel` unit tests (#56), stable `RecentProjectSummary` id (#57), `PlayerViewModel` `@MainActor` (#58).

## Phase 2 — Distribution (make it a product)

- **Final name decision** — blocked on App Store Connect availability. Test a distinctive base brand alone and in full-name variations such as `<Brand>: Video Ingest`, then choose a complementary subtitle. Follow the strategy and checklist in [`NAMING.md`](NAMING.md); the code rename remains a one-file change plus the `AppBrand.swift` checklist.
- **Real brand asset**: replace the generated placeholder icon and SwiftUI logo with final artwork; commit real icon assets. Do this together with the name decision.
- ✅ **Developer ID signing + notarization, DMG packaging, release workflow** — shipped as `.github/workflows/release.yml`: push a `vX.Y.Z` tag → Release build + tests → optional signing/notarization (activates automatically once the Apple secrets are configured in repo settings) → DMG → GitHub Release. Unsigned DMGs publish for testing until the secrets exist.
- ✅ **Versioning + changelog** — `CHANGELOG.md` added; the release workflow stamps `MARKETING_VERSION` from the tag and the build number from the CI run.
- ✅ **Updates** — Help → Check for Updates… queries GitHub Releases and compares against `MARKETING_VERSION` (`GitHubUpdateCheckService`, #66). Apple-frameworks-only; no Sparkle. Mac App Store build optional later (sandboxing is already in place).
- **Reliability and hardware compatibility matrix** (#104) — publish what has actually been tested: cards, readers, hubs, drives, filesystems, interruption scenarios, and recovery results, dated and tied to an app version. Trust claims from a new vendor are worth nothing unless they are checkable, and an untested configuration is listed as untested. Fed by the #55 hardware runs, so producing it is a byproduct of testing rather than separate work.
- ✅ **First-launch onboarding** — five-step walkthrough on first launch, re-openable via Help → Welcome; plus Help → Keyboard Shortcuts cheat sheet.
- ✅ **Save Diagnostics** — Help → Save Diagnostics Report… writes a local plain-text report (app, system profile, settings, recent projects). Local-first; no telemetry.

## Phase 3 — Safe media release (the launch wedge)

This is the differentiator, and it does not exist in the app yet. Everything above is table stakes that competitors already ship; this is the part that is ours.

The promise is one sentence: **when the checkmark appears in the menu bar, the card has met the configured safety conditions and can be ejected.** The anxiety this product exists to remove is highest exactly when the operator has walked away from the Mac, so the status has to be glanceable and has to survive the main window being closed.

- **Menu-bar card status and Eject All Safe Cards** (#93) — persistent per-card state: in use, blocked with the reason, or safe to remove. Untracked removable media is offered separately, labeled as available to eject and never presented as verified by us. Ejecting is an unmount only.
- **Physical card lifecycle** (#94) — assign → record → return → verified ingest → safe to remove → clear to format → reassign, with persistent card identity across mounts and a card history.

Two states, deliberately distinct, and conflating them is how footage gets destroyed:

| State | Means |
|---|---|
| **Safe to remove** | The app has stopped using the source. |
| **Clear to format** | The required verified copies and team policy have been satisfied. |

The app never formats a card. "Clear to format" is a statement to the operator, not an action we perform.

Both items depend on per-destination verification records (#91) and a defensible verification default (#92). Building the checkmark on top of a size check would be worse than not shipping it at all.

## Phase 4 — Workflow-completing features (priority order)

1. **Proof artifacts** — wire the existing, tested `MHLReportService` into the export UI (#67; generation is already written but currently unreachable), then add a human-readable **PDF transfer report** (#95). MHL is for other tools; the PDF is what a client, producer, or insurer actually reads. Both must read the same verification records and never describe a size-checked copy as checksum-verified.
2. **Contact sheets / filmstrip hover-scrub** (#68, #69, #70) — settings key and background-work plumbing already exist; implement generation from copied media only, then re-enable the hidden toggle.
3. **Finder tags + XMP sidecar export** (#71, #72, #73) — implement the writers behind the reserved `finderTagsExport` / `xmpSidecarExport` keys, then re-enable the hidden toggles. Sidecars only; never write into MP4/MOV media.
4. **FCPXML / Resolve-friendly handoff** (#74, #75) — carry ratings, tags, and notes into the NLE instead of folder-open only.
5. **Project templates** (#76) and ingest rename/folder-pattern tokens (#77). Defaults stay safe: preserve original filenames, flat copy, never overwrite.
6. **Review and delivery** — repeated-take grouping (#99), client-safe review packages (#105), and proxy generation (#106). Proxies are what make review possible away from the ingest SSD and make a review package a sendable size.

## Performance and Apple Silicon

Shipped baseline: bounded in-memory thumbnail cache and adjacent-preview prewarming. Continue to measure time-to-first-thumbnail and time-to-first-preview before adding heavier processing.

- Runtime performance profiles (arm64, memory, Metal, tier, recommended concurrency); modes Automatic, Fast, Balanced, Quality.
- `BackgroundWorkCoordinator` manages ingest copy, verification, thumbnails, analysis, exports, and future contact sheets/cloud transfers; every background task must be cancelable.
- No main-thread scanning, thumbnailing, or analysis; frequent safety saves during ingest.
- Log scan duration, copy speed, verification speed, thumbnails/sec, analysis time, and failure counts.

## Local intelligence (after Phase 4)

Everything here runs on-device. Local processing is not only a privacy position — it is the commercial one. A feature with no per-minute cost can ship inside a one-time price; a cloud dependency cannot.

**Technical checks (deterministic, highest value first):**

- **Audio health** (#96) — level, silence, clipping, missing and imbalanced channels. This is the largest current gap: analysis today is video-only. Dead audio is the most expensive discoverable failure in event and interview work, and the easiest to detect without false positives.
- **Technical consistency** (#97) — codec and frame-rate mismatch against the project's dominant profile, gaps in camera clip numbering, implausible timestamps, and suspiciously short takes. Cheap metadata comparisons that catch expensive mistakes.
- **Session-relative outliers** (#98) — flag the clip unlike the rest of its session rather than comparing against fixed thresholds. This is the fix for the false positives documented in the README disclaimers.

**Transcription (#100, #101):**

On-device transcription with timestamp-linked search, vocabulary corrections, and SRT/WebVTT subtitle export. Works fully offline with no API key. Vocabulary persists across projects, so each project transcribes better than the last.

> **Corrected direction.** Transcription was previously listed under cloud Phase C. It is a **local Phase 2 capability**. The positioning, the pricing model, and the privacy promise all depend on it running on-device.

**Suggestions:**

- **Rule-based:** better focus/stability/face-visibility scoring, social-clip candidate scoring, best-frame thumbnails, talking-head detection, high-motion detection, lighting warnings.
- **Apple frameworks (Vision, Core Image, Core ML, Foundation Models)** (#80): suggest tags, scene names, folder names, descriptions, social selects; summarize sessions/projects; duplicate detection; best thumbnail frames. Never upload by default, suggestions always editable, never auto-identify people by name. `FoundationModelSuggestionService` stays a guarded placeholder until a real integration lands.

## Portable core and archive (after Phase 4)

The order here is deliberate and comes straight from the product thesis: finish a trustworthy Mac product first, **document the project format second**, then extract the portable safety logic — before any Windows or tablet work begins.

- **Document and version the project format** (#102) — an undocumented format is not a portable format. Relative media paths, per-destination records, card identity, transcripts, analysis, archive locations, migration rules, and a requirement that unknown fields survive a round-trip so an older app never destroys a newer app's data. Writing the spec is also the cheapest way to find modeling mistakes before a second implementation has to reproduce them.
- **Extract the portable engine** (#103) — copy, verification, manifest, preflight matching, and safety-policy evaluation into a module with no AppKit/SwiftUI dependency, behind platform adapters for volume discovery, permissions, notifications, decoding, and eject. Design filename, path, and timestamp rules for Windows, exFAT, and case-sensitivity now. Keep native UI per platform; never port the interface.
- **Archive** (#107) — persistent volume identity, a catalog queryable while the media volume is offline ("which drive is this shoot on"), and read-only archive re-verification against stored checksums so the verified-copy guarantee stays true past ingest day.

Only after all of the above: Windows workstation, then tablet field ingest, then a phone companion (#82).

## Cloud Storage (after Phase 4)

- **Phase A:** treat mounted synced folders (Google Drive, OneDrive, Dropbox, iCloud, Box, Synology, SMB/NAS) as sources/destinations with cloud badges, availability warnings, and post-ingest sync reminders.
- **Phase B:** cloud-aware workflow — online-only detection, keep-awake helper, backup verification summary.
- **Phase C:** direct uploads (Drive, OneDrive, Dropbox, Box, B2, Wasabi, S3, WebDAV) with resumable, verified uploads and a local queue. Opt-in only, with clear warnings; local processing always remains available.
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

### What we are actually selling

Not faster file copying. The product removes the highest-anxiety decision in the workflow — whether irreplaceable footage exists in enough verified places to pull or reuse the card — and then saves time after ingest through technical checks, searchable speech, recorded decisions, and editor handoff.

That ordering matters for sequencing. The trust layer (Phase 1) and the release wedge (Phase 3) are the product. Everything else is what keeps it useful after the initial anxiety is gone.

Two risks govern the plan:

- **Reliability credibility.** One corrupted or falsely certified transfer permanently ends the brand. Smart features wait until the safety state machine, reports, and real-hardware fault testing are proven.
- **Feature sprawl.** Matching DIT, MAM, NLE, cloud review, and AI products at once produces an unfinished suite. The launch wedge stays card safety, reports, culling, and editor-ready handoff.

## Tracking

[#83](https://github.com/DurantTL/ClipVault/issues/83) is the master tracker for Mac v1 and maps every issue in this roadmap to its epic.
