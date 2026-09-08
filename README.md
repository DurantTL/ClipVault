# SlateBox

**Ingest. Verify. Cull. Hand off.**

SlateBox is a native macOS SwiftUI app for safe video ingest, verification, preview, culling, and editor handoff. It copies video files from a camera card or source folder to a destination project folder, verifies the copies, generates thumbnails, and lets you review and organize the copied media without ever touching the original source.

> **Brand name is not final.** The public name is still being decided (candidates: Cullect, TakeHarbor, SlateBox, ClipVault). User-visible strings flow through `AppBrand.swift`, so a rename is a one-file change plus a checklist. The hidden on-disk identifiers keep the stable `clipvault` spelling permanently — see [On-disk names](#on-disk-names) and [`NAMING.md`](NAMING.md).

## Contents

- [Requirements](#requirements)
- [Build and release](#build-and-release)
- [Ingest workflow](#ingest-workflow)
- [Verification](#verification)
- [Library, culling, and review](#library-culling-and-review)
- [Export and editor handoff](#export-and-editor-handoff)
- [Local analysis](#local-analysis)
- [Safety rules](#safety-rules)
- [Recovery behavior](#recovery-behavior)
- [Source permissions](#source-permissions)
- [Project files](#project-files)
- [Known limitations](#known-limitations)
- [Documentation](#documentation)

## Requirements

SlateBox targets Apple Silicon Macs; the app target builds for `arm64` only.

| | |
|---|---|
| Minimum | Apple Silicon Mac, 16 GB RAM |
| Recommended | M2 Pro / M3 Pro / M4 Pro or better, 32 GB+ for large event projects |
| Storage | Fast SSD recommended |
| macOS | macOS 15 or newer recommended for best performance |
| Build | Xcode 15+ on macOS 14+ |

SlateBox picks a performance profile automatically from architecture, physical memory, and Metal device availability. Performance Mode (Automatic, Fast, Balanced, Quality) tunes thumbnail concurrency, analysis sampling, and background work priority.

The app uses Apple frameworks only — SwiftUI, AVFoundation, AVKit, Foundation, UniformTypeIdentifiers, CryptoKit, Vision, and AppKit. There is no FFmpeg and no third-party dependency.

## Build and release

Open `SlateBox.xcodeproj` in Xcode, select the `SlateBox` scheme, and run. From the command line:

```bash
xcodebuild -project SlateBox.xcodeproj -scheme SlateBox \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Releases are cut by pushing a version tag:

```bash
git tag v1.0.0 && git push origin v1.0.0
```

The `Release SlateBox` workflow builds a Release app, runs the test suite, packages a DMG, and publishes a GitHub Release with the DMG attached. Signing and notarization run automatically when the repository secrets `MACOS_CERTIFICATE_BASE64`, `MACOS_CERTIFICATE_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_SPECIFIC_PASSWORD` are configured. Without them the workflow still publishes an unsigned DMG for testing (right-click → Open on first launch).

DMG builds can use **Help → Check for Updates…**, which queries GitHub Releases for a newer version. This is a manual check only; there is no Sparkle auto-update.

### Help menu

- **Welcome** reopens the first-launch onboarding walkthrough.
- **Keyboard Shortcuts** shows the culling and navigation cheat sheet.
- **Save Diagnostics Report…** writes a local plain-text report (app version, system profile, settings, recent project paths) for support. It stays on your Mac; nothing is uploaded.

### App icon assets

Binary PNG icons are intentionally git-ignored so text-only changes can build in source control. To generate local placeholder icons on a Mac:

```bash
make icons   # or: python3 Scripts/generate_app_icon.py
```

This writes `ClipVault/Assets.xcassets/AppIcon.appiconset/icon_16x16_1x.png` through `icon_512x512_2x.png` plus `Contents.json`. Run **Product → Clean Build Folder** afterward. The SwiftUI in-app logo works without generated assets.

## Ingest workflow

1. Click **New Ingest** and choose a source — an SD card, mounted drive, or folder.
2. SlateBox scans the source and detects the card layout:
   - **Sony:** prioritizes `PRIVATE/M4ROOT/CLIP`. Proxy files in `PRIVATE/M4ROOT/SUB` are skipped unless **Include Proxy Files** is enabled.
   - **Canon/DCF:** detects a root `DCIM` folder and scans video formats (`.MP4`, `.MOV`, `.CRM`). Photo and sidecar formats (`.JPG`, `.CR3`, `.THM`) are ignored.
   - **Generic:** recursive video scan.
3. Review detected **sessions**. Clips are grouped by recording date with a 90-minute gap split, so a day with several shoots can be selected in chunks. Session cards show the time range, clip count, total size, and card type, and expand to individual files with checkboxes.
4. Select what to copy using the session and clip checkboxes, or Select All, Clear Selection, Select Today, Select New Only, or Select by Date.
5. Choose a destination, optional Backup 1 and Backup 2 destinations, a project name, and an optional shoot subfolder.
6. Set folder structure (**Flat** or **Preserve Source Structure**), proxy inclusion, verification mode, and thumbnail quality.
7. Optionally run a [Preflight Media Check](#preflight-media-check).
8. Click **Start Ingest**. SlateBox confirms free space, streams each file in chunks through a `.clipvault-partial` temp file, verifies the result, then generates metadata and a thumbnail for successfully copied and verified clips only.
9. The library opens for preview, culling, and organization.

Start Ingest stays disabled until there is a destination, a project name, and at least one selected clip.

Ingest can be paused and resumed between chunks. Keep the card and destination drive connected until copy and verification finish.

### Camera and card metadata

New Ingest includes a **Camera / Card Info** section for camera label, camera name/model, operator, card or reel name, and optional shoot day. SlateBox suggests common and recently used labels, saves the assignment in the project JSON, and applies it to every clip copied from that source. Clip metadata can be edited later as an override.

### Renaming

Rename is off by default. When enabled, files are copied as `[Project Name]-[YYYY][MM][DD]-[Sequence].EXT`, and the original filename is preserved in `.clipvault-project.json`.

### Backups and network destinations

Backups are copied from the verified primary destination so the card is read once. Mounted NAS folders are treated as normal folders; transfers may be slower and disconnects should be retried once the share is back. "Cloud-synced folder support" means local folders managed by iCloud Drive, Dropbox, Google Drive, or OneDrive — SlateBox does not upload to cloud providers directly.

### Preflight Media Check

Before copying, New Ingest can compare the scanned source clips against the destination, configured backups, and recent projects. Matching is by file identity — filename, size, modified date, and duration where available — never by folder location, so renamed project folders do not defeat detection.

Each clip is classified as New, Already at Destination, Already in Project, Already on Backup, Possible Duplicate, or Same Name Different Size. The selection can automatically keep only new media. Preflight never modifies media, and ingest still uses safe `_1`/`_2` naming regardless of the result.

## Verification

| Mode | What it checks | Cost |
|---|---|---|
| **Fast size check** (default) | Copied file size matches the source | Does not reread the card |
| **Strong SHA256** | Byte-level hash of source and destination | Reads both source and destination; slow for large 4K60 10-bit files |

> **Known gap:** the shipping default is a size check, which cannot detect corruption that preserves file length. Full-content verification by default — hashing the source once during the copy rather than in a second pass — is tracked in [#92](https://github.com/DurantTL/ClipVault/issues/92) and gates any paid trust claim. Reports and exports must never describe a size-checked copy as checksum-verified.

## Library, culling, and review

The library uses a compact sidebar, a flexible clip grid as the main workspace, and a collapsible inspector (toggled from the toolbar; the preference persists).

### Ratings and culling

Clips carry both a Keep/Maybe/Reject cull status and a 0–5 star rating, kept in sync:

| Rating | Status |
|---|---|
| 0 | Unrated |
| 1 | Reject |
| 2–3 | Maybe |
| 4–5 | Keep |

Setting a rating updates the status. Setting a status directly only adjusts the rating when the two disagree, so a 5-star clip marked Keep stays 5-star. Project files without ratings open normally, deriving ratings from the saved cull status.

### Keyboard shortcuts

| Key | Action |
|---|---|
| `Space` | Preview selected clip, or play/pause in preview |
| `5` | Favorite / Best Keep (5★) |
| `4` | Keep (4★) |
| `3` | Maybe (3★) |
| `2` | Maybe – Low (2★) |
| `1` | Reject (1★) |
| `0` | Clear rating / Unrated |
| `←` / `→` | Select previous or next clip |
| `⌘ Click` | Add or remove a clip from the selection |
| `⇧ Click` | Select a range of visible clips |
| `⌘ A` | Select all visible clips |
| `⌘ R` | Reveal selected clip(s) in Finder |
| `Esc` | Close preview, or clear the multi-selection |

### Filters, folders, and tags

The sidebar keeps workflow filters deliberately small: Unrated, Keep, Maybe, Reject, and Needs Review. Use project folders for the editing structure you want in Finder, and tags for descriptive facets such as Sermon, B-Roll, 4K, or Faces. This avoids turning every detected property into a permanent sidebar folder.

Sorting covers Ingest Order, Shot Time, Filename, Created Date, Modified Date, Duration, File Size, Cull Status, Rating/Keep Status, and Camera Type, ascending or descending.

**Shot Time** resolves in order: manual override, camera/media metadata, file creation date, file modified date, then remaining fallbacks. Clips store `capturedAt`, `shotStartTime`, `manualShotTime`, and `shotTimeSource`; the inspector can set, use current time for, or clear a manual override.

### Batch actions

The grid supports ⌘-click, ⇧-click range select, ⌘A, and Escape. Batch actions apply to the whole selection: status and rating, add/remove tags, move to folder, regenerate thumbnails, and Batch Edit Metadata (tags append/replace/remove, people, location, scene, shot type, notes, flags).

### Partial libraries

Partial ingest libraries show a banner with **Resume Ingest** and **Reveal Project Folder**. Resume retries every unfinished or failed clip. Pending clips stay in project metadata as non-destructive records and are not previewed unless a destination file exists.

### Responsiveness

Library thumbnails are decoded once into a bounded in-memory cache rather than repeatedly from disk during SwiftUI redraws. Preview navigation prewarms adjacent copied clips' AVFoundation metadata so Next/Previous starts sooner, without generating proxies or reading a source card.

## Export and editor handoff

The Export menu copies clips into an editor-ready folder: Keeps, Keep + Maybe, 4–5 star clips, or the current selection. Exports **copy** — never move — from copied project media only, never overwrite (safe `_1`, `_2` names), show progress and a summary, and reveal the folder when done. Folder handoff targets Finder, DaVinci Resolve, and Final Cut Pro; SlateBox says so when a requested editor is not installed.

Reports: Clip Report CSV, Keep List CSV, Reject List CSV, verification and analysis CSVs, and project metadata JSON. CSV reports include filename, cull status, duration, file size, resolution, frame rate, codec, tags, notes, source path, and destination path.

The Batch menu can create symbolic-link aliases in `Aliases/<name>/` for selected copied clips. Aliases are organization only: they never point at source-card media, and removing one never alters the copied original.

## Local analysis

Analysis runs offline with Apple APIs on **copied destination files only**, storing results in the project JSON. Modes are Off, Fast, Balanced, and Detailed. AVFoundation samples a small number of frames — Fast samples 3, Balanced samples 5 or roughly every 10 seconds, Detailed samples every 2–5 seconds with a cap. SlateBox never analyzes every frame.

Detected properties populate inspector fields and smart folders:

- **Focus** — Possibly Out of Focus
- **Faces** — Faces, Group Shots, Close Faces, Low Face Visibility
- **Stability** — Possibly Shaky, Stable Clips, High Motion
- **Exposure** — Dark Clips, Bright Clips, Low Contrast, Balanced Exposure
- **Rule-based tags** — 4K, 60p, Has Audio, No Audio, Short Clip, Long Clip, Large File, Sony
- **Failed Analysis**

Focus, stability, and exposure roll into a 0–100 quality score shown on clip cards and sortable via "Analysis Quality". Each analyzed clip gets a suggested 0–5 rating and, where warranted, Top Pick or Social Pick suggestion tags with matching smart folders.

**Suggestions are never applied automatically.** Apply them per clip from the inspector, or in bulk via "Apply Suggested Ratings to Unrated Clips", which never overwrites a rating a person set.

### Accuracy disclaimers

These scores are advisory and can be wrong:

- **Focus** is estimated from luminance edge energy, and can misread intentional soft focus, background shots, haze, or low-detail scenes.
- **Exposure and contrast** are estimated from sampled frames; the tags are organizational hints, not judgements.
- **Stability** is estimated from sampled frame differences and may flag intentional handheld movement or fast pans.
- **White balance** is stored as an approximate Kelvin-style value when camera metadata is unavailable, shown as "Approx." with a confidence, because true white balance is often absent from MP4/MOV metadata.

Session-relative comparison, which would reduce these false positives by flagging clips unlike the rest of their session rather than against fixed thresholds, is tracked in [#98](https://github.com/DurantTL/ClipVault/issues/98).

### Privacy

All analysis runs offline. SlateBox does not upload frames, face data, clip metadata, or transcripts to any service. Vision detects face presence, approximate counts, close faces, group shots, low visibility, and an anonymous unique-face appearance estimate. **SlateBox does not identify people and does not assign real names.** Face features are for organization only.

A local-only `LocalSuggestionService` architecture exists with a rule-based implementation and a guarded `FoundationModelSuggestionService` placeholder. SlateBox does not use cloud AI and does not require Foundation Models to build.

See [`docs/privacy.md`](docs/privacy.md).

## Safety rules

These hold for every feature. They are enforced in code and covered by the CI test suite.

**Sources are read-only, always:**

- Never delete source files.
- Never modify original media.
- Never format or erase cards.
- Never write thumbnails or metadata to source cards.

**Destinations are append-only:**

- Never overwrite destination files; conflicts receive `_1`, `_2`, and so on.
- Copy first, verify second.
- Streaming copies write to `.clipvault-partial` and only move into place once fully copied.

**Copies are the working set:**

- New Ingest may generate temporary read-only thumbnails from source media for identification only, stored in `~/Library/Caches/ClipVault/IngestPreviewThumbnails/`.
- Full playback, culling, rating, metadata editing, analysis, aliases, and export use copied project files only.
- Library thumbnails are generated from copied files only, stored in `.clipvault-cache/thumbnails/`.
- Production metadata is saved to the project JSON, not written into MP4 or MOV files.
- Culling changes project metadata only. Physical sorting moves copied files inside the destination project folder, and undo restores clip path metadata.
- Folder delete removes the folder assignment from project metadata; it does not delete media.

**Failures are contained:**

- If copy or verification fails for one clip, the error is recorded on that clip and the remaining clips continue.
- Failed clips do not run metadata extraction or thumbnail generation.
- Thumbnail failure never invalidates a copied and verified clip; the UI falls back to a generic video icon.
- Canceling during a large copy leaves copied files in place, leaves sources untouched, and marks the project incomplete.

## Recovery behavior

- A known destination capacity smaller than the selected media blocks Start Ingest. When a NAS cannot report capacity, SlateBox shows an advisory rather than incorrectly blocking the job.
- Low remaining space is called out before copying starts.
- Disk-full, disconnected-volume, lost-permission, and read-only errors produce recovery instructions instead of raw filesystem messages.
- Failed and canceled ingests stay marked incomplete and reopenable. Valid partial files are retained for a verified resume, and source media remains untouched.
- Project-save and report-export failures appear in the library. A failed project save can be retried after reconnecting the volume or freeing space.
- Backup folders are reopened through their security-scoped bookmarks. A backup problem is recorded as a warning while the verified primary copy remains usable.

> Per-destination copy and verification state — so a backup failure can never obscure which destinations actually hold a verified copy — is tracked in [#91](https://github.com/DurantTL/ClipVault/issues/91).

Hardware recovery validation against real disconnects is tracked in [#55](https://github.com/DurantTL/ClipVault/issues/55); see [`TESTING.md`](TESTING.md).

## Source permissions

SlateBox is sandboxed:

- Volumes macOS reports as removable (most SD cards) are read through the read-only removable-media entitlement and never show a SlateBox picker. macOS itself may show a one-time removable-volume prompt.
- External SSDs, fixed card readers, network volumes, and manual folders need a one-time grant through the source picker. SlateBox saves a security-scoped bookmark so the grant survives relaunches.
- Once granted in a session, a source stays granted for the life of the New Ingest view model. Swapping between cards and drives never re-prompts for an already-granted source.
- Persisted bookmarks are refreshed while their security scope is active. A grant is re-requested only when a volume remounts at a path the saved bookmark does not cover.
- Stale bookmarks self-heal: when a file server or volume is renamed, the bookmark is re-created from the resolved location and persisted.

## Project files

Each project folder contains a hidden `.clipvault-project.json` metadata file. **Open Existing Project** accepts either the project folder or the hidden JSON file. Recent projects are stored as metadata-file paths and show a friendly error when an external SSD or NAS volume is unavailable.

Clip metadata includes cull status, rating, production tags, people, location, scene, shot type, notes, favorite/B-roll/sermon/interview/social flags, shot-time fields, and analysis results.

The project JSON carries a `schemaVersion` field so future migrations can be detected and handled safely. Older project files without `schemaVersion` remain openable with backward-compatible defaults. Codable unit tests protect project and clip JSON from breaking changes, including partial and canceled ingests that must stay reopenable.

A written, versioned specification for this format is tracked in [#102](https://github.com/DurantTL/ClipVault/issues/102).

### On-disk names

The hidden identifiers — `.clipvault-project.json`, `.clipvault-cache/`, `.clipvault-partial`, and the `~/Library/Caches/ClipVault/` preview cache — intentionally keep the legacy `clipvault` spelling. They are **permanent format identifiers**, independent of the product name, so every existing project stays openable regardless of future renames. All are defined in one place, `AppBrand.swift`.

## Known limitations

**Not implemented:**

- No menu-bar card status or safe-eject indicator ([#93](https://github.com/DurantTL/ClipVault/issues/93)) and no card lifecycle tracking ([#94](https://github.com/DurantTL/ClipVault/issues/94)).
- No transcription or transcript search ([#100](https://github.com/DurantTL/ClipVault/issues/100)).
- No audio analysis — current analysis covers video only ([#96](https://github.com/DurantTL/ClipVault/issues/96)).
- No FCPXML or EDL project export; editor handoff is folder-based ([#74](https://github.com/DurantTL/ClipVault/issues/74), [#75](https://github.com/DurantTL/ClipVault/issues/75)).
- No MHL export reachable from the UI. `MHLReportService` exists and is tested, but is not yet wired to a menu action ([#67](https://github.com/DurantTL/ClipVault/issues/67)).
- No PDF reports ([#95](https://github.com/DurantTL/ClipVault/issues/95)); CSV and JSON only.
- No contact sheets or filmstrips ([#68](https://github.com/DurantTL/ClipVault/issues/68)); one cached thumbnail per clip.
- No proxy generation ([#106](https://github.com/DurantTL/ClipVault/issues/106)).
- No cloud sync, cloud AI, editing timeline, SD formatting, permanent deletion, or multi-user collaboration. Direct Dropbox, Google Drive, and OneDrive upload APIs are not implemented — use their local synced folders.

**Constraints:**

- Preview, metadata, and thumbnail support depend on AVFoundation codecs available on the user's Mac. `.CRM` files may copy and verify even when preview is unavailable.
- Recent projects reopen automatically only while the project folder, SSD, or NAS mount is available at the expected location or resolvable by bookmark.
- The app icon and in-app logo are polished placeholders, not final brand assets ([#61](https://github.com/DurantTL/ClipVault/issues/61)).
- Analysis is rule-based and Vision-based only; no cloud AI and no heavy Core ML model is included.

## Documentation

| Document | Purpose |
|---|---|
| [`ROADMAP.md`](ROADMAP.md) | Phases, priorities, and product direction |
| [`TESTING.md`](TESTING.md) | Manual regression checklist and hardware validation |
| [`NAMING.md`](NAMING.md) | Brand candidates, limits, and the rename process |
| [`AGENTS.md`](AGENTS.md) | Contributor and agent rules |
| [`CHANGELOG.md`](CHANGELOG.md) | Release history |
| [`docs/privacy.md`](docs/privacy.md) | Privacy policy — local-first processing, face-data limits |
| [`docs/support.md`](docs/support.md) | Contact, diagnostics, requirements |

Issue [#83](https://github.com/DurantTL/ClipVault/issues/83) is the master tracker for Mac v1.
