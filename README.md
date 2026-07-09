# SlateBox

**Ingest. Verify. Cull. Hand off.**

SlateBox is a native macOS SwiftUI app for safe video ingest, preview, culling, and folder sorting. It copies video files from an SD card or source folder to a destination project folder, verifies the copies, generates thumbnails, and lets users review and sort the copied media without touching the original source.


## System requirements and performance

SlateBox is designed for Apple Silicon Macs and the app target builds for `arm64` only. Recommended hardware:

- Apple Silicon M2 or newer.
- M2 Pro / M3 Pro / M4 Pro or better for large 4K/10-bit workflows.
- 16 GB RAM minimum recommended.
- 32 GB+ recommended for large event projects.
- Fast SSD recommended.
- macOS 15+ or newer recommended; the deployment target may remain lower, but newer systems get the best performance.

SlateBox uses an automatic performance profile based on safe Apple APIs: arm64 architecture, physical memory, and Metal device availability. Performance Mode can be set to Automatic, Fast, Balanced, or Quality to tune thumbnail concurrency, local-analysis sampling, contact-sheet preparation, and background work priority.

## Build

Open `SlateBox.xcodeproj` in Xcode 15 or newer on macOS 14+, select the `SlateBox` scheme, and run. The app uses only Apple frameworks: SwiftUI, AVFoundation, AVKit, Foundation/FileManager, UniformTypeIdentifiers, CryptoKit, and AppKit where macOS-specific APIs are needed.

## Ingest workflow

1. Click **New Ingest**.
2. Choose a source folder such as an SD card or camera-card copy.
3. Choose a destination folder such as an SSD or mounted NAS folder.
4. Name the project. The default is date-based.
5. SlateBox scans Sony cards by using `PRIVATE/M4ROOT/CLIP` when present.
6. Proxy files in Sony `PRIVATE/M4ROOT/SUB` are skipped by default unless **Include Proxy Files** is enabled. Non-Sony folders continue to scan recursively.
7. Click **Start Copy**. SlateBox streams each file in chunks, updates progress during large copies, verifies the result, then generates metadata and a thumbnail only for successfully copied and verified clips.
8. The library opens so clips can be previewed, marked Keep/Maybe/Reject, revealed in Finder, and moved into custom folders.

### Camera and card metadata

New Ingest includes a **Camera / Card Info** section for a camera label, camera name/model, operator, card or reel name, and optional shoot day. SlateBox suggests common labels plus recently used labels, saves the source assignment in the project JSON, and applies it to every copied clip from that source. Clip metadata can still be edited later as an override.

## Safety behavior

- SlateBox never deletes source files.
- SlateBox never formats or erases cards.
- SlateBox never modifies original media.
- SlateBox never writes thumbnails to source cards.
- New Ingest may generate temporary read-only thumbnails from source media for identification only, stored in `~/Library/Caches/SlateBox/IngestPreviewThumbnails/`.
- Full playback preview, culling, rating, metadata editing, analysis, aliases, export, and library thumbnails use copied project files only.
- Library thumbnails are generated from copied files only and stored in `.SlateBox-cache/thumbnails/`.
- SlateBox never overwrites destination files; conflicts receive `_1`, `_2`, etc.
- Ingest copy uses security-scoped access for selected source, destination, and project folders so SD cards, external SSDs, and mounted NAS locations continue working after the user grants access.
- If ingest is canceled during a large file copy, copied files are left in place, source files are untouched, and the project is marked incomplete.
- If copy or verification fails for one clip, SlateBox records the error on that clip and continues with the remaining clips.
- Failed clips do not run metadata extraction or thumbnail generation.
- Thumbnail failures do not invalidate a copied and verified clip; the UI falls back to a generic video icon.
- Culling only changes project metadata.
- Physical sorting only moves copied files inside the destination project folder, and undo restores clip path metadata.

## Source permission behavior

SlateBox is sandboxed, so source access follows these rules:

- Volumes macOS reports as removable (most SD cards) are readable through the read-only removable-media entitlement and never show a SlateBox picker. macOS itself may show a one-time "removable volume" system prompt for the app.
- External SSDs, fixed card readers, network volumes, and manual folders need a one-time grant through the source picker. SlateBox saves a security-scoped bookmark so the grant survives relaunches.
- Once a source is granted in a session, its access stays active for the life of the New Ingest view model. Swapping between cards and drives in the sources list must never re-prompt for a source that was already granted.
- Persisted bookmarks are refreshed while their security scope is active, and a grant is re-requested only when a volume remounts at a different path than the saved bookmark covers.

## Verification

The default verification mode is **Fast size check**, which confirms the copied file size without rereading the SD card more than necessary. **Strong SHA256** remains available in Settings for users who want a safer byte-level hash comparison, but it is slower for large Sony a7R V 4K60 4:2:2 10-bit files because it reads both the source media and copied destination media.

## Project files and recent projects

Each project folder contains a hidden `.SlateBox-project.json` metadata file. **Open Existing Project** accepts either the project folder or the hidden JSON file. Recent projects are stored as project metadata-file paths and display a friendly error if an external SSD or NAS volume is disconnected or unavailable.

## Sony a7R V focus

The MVP is focused on Sony a7R V/XAVC-style workflows: `PRIVATE/M4ROOT/CLIP` prioritization, proxy exclusion by default, optional proxy inclusion from `PRIVATE/M4ROOT/SUB`, chunked copy with cancel support, fast verification by default, and AVFoundation-based metadata/thumbnail extraction without transcoding, LUTs, or color transforms.

## Known limitations

- No cloud sync, AI analysis, duplicate detection, editing timeline, NLE export, SD formatting, permanent deletion, or multi-user collaboration.
- Preview, metadata, and thumbnail support depends on AVFoundation codecs available on the user's Mac.
- The first version generates one cached thumbnail per clip, not filmstrips/contact sheets.
- Recent projects can only reopen automatically while the project folder, external SSD, or NAS mount is available at the expected location or resolvable by its bookmark.

## Current SlateBox polish pass

SlateBox is a native macOS SwiftUI ingest and culling app focused on safe copy, verification, preview, and fast keyboard-based review.

### Current features

- Project dashboard with recent project cards, cover thumbnails, clip counts, total size, cull counts, and quick Open / Reveal / Remove actions.
- Guided ingest flow for source selection, destination selection, project naming, scan summary, copy progress, cancel state, and Sony card detection.
- Project library with smart filters, custom folders, production tags, thumbnail size controls, sort controls, batch rating actions, and CSV/JSON export entry points.
- Metadata inspector with clip summary, culling status, technical metadata, production metadata, automatic tags, and source/destination paths.
- Local rule-based analysis foundation for automatic tags such as 4K, 60p, Has Audio, No Audio, Short Clip, Long Clip, Large File, and Sony.

### Ingest workflow

1. Choose an SD card, mounted drive, or folder as the source.
2. SlateBox scans common video formats and prioritizes Sony `PRIVATE/M4ROOT/CLIP` folders when found.
3. Choose a destination parent folder and enter a project folder name plus an optional shoot/subfolder name.
4. Pick flat or source-preserving folder structure, proxy inclusion, verification mode, and thumbnail quality.
5. Start copy and keep the SD card and destination drive connected until ingest completes.

### Keyboard shortcuts

- Space: Preview selected clip.
- 1–5: Set star rating (5 = Favorite/Best Keep, 4 = Keep, 3 = Maybe, 2 = Maybe-Low, 1 = Reject).
- 0: Clear rating / Unrated.
- Left / Right Arrow: Select previous or next clip.
- Command-Click: Add or remove a clip from the multi-selection.
- Shift-Click: Select a range of visible clips.
- Command-A: Select all visible clips.
- Command-R: Reveal selected clip(s) in Finder.
- Escape: Close preview, or clear the multi-selection.

### Ratings and culling

Clips carry both a fast Keep/Maybe/Reject cull status and a 0–5 star rating. Setting a rating updates the status automatically (0 → Unrated, 1 → Reject, 2–3 → Maybe, 4–5 → Keep). Setting a status directly only adjusts the rating when the two disagree, so a 5-star clip marked Keep stays 5-star. Old project files without ratings open normally; ratings are derived from the saved cull status.

### Multi-select, batch actions, and bulk metadata

The library grid supports Command-click, Shift-click range select, Command-A, and Escape. Batch actions apply to the whole selection: status/rating, add/remove tags, move to folder, thumbnails, and Batch Edit Metadata (tags append/replace/remove, people, location, scene, shot type, notes, and flag set/clear).

The sidebar intentionally keeps workflow filters small: Unrated, Keep, Maybe, Reject, and Needs Review. Use project folders for the editing structure you want to see in Finder and tags for descriptive facets such as Sermon, B-Roll, 4K, or Faces. This avoids turning every automatically detected property into a permanent sidebar folder.

### Local responsiveness

Library thumbnails are decoded once into a bounded in-memory cache rather than repeatedly from disk during SwiftUI redraws. Preview navigation prewarms the adjacent copied clips’ AVFoundation metadata, so Next/Previous can start sooner without generating proxies or reading a source card.

### Export and editor handoff

The Export menu copies clips into an editor-ready folder: Keeps, Keep + Maybe, 4–5 star clips, or the current selection. Exports copy — never move — from copied project media only, never overwrite (safe `_1`, `_2` duplicate names), show progress and a summary, and reveal the folder when done. CSV reports cover the full clip list, keep list, reject list, verification, and analysis; project metadata exports as JSON.

The Batch menu can also create symbolic-link aliases in `Aliases/<name>/` for the selected copied clips. The links are organization only: they never point to source-card media, and removing an alias never alters the copied original. The Export menu includes folder handoff choices for Finder, DaVinci Resolve, and Final Cut Pro; SlateBox tells you when a requested editor is not installed.

### Analysis-assisted culling

Local analysis rolls focus, stability, and exposure into a 0–100 quality score shown on clip cards and sortable via "Analysis Quality". Each analyzed clip gets a suggested 0–5 rating and, where warranted, "Top Pick Suggestion" / "Social Pick Suggestion" tags with matching smart folders. Suggestions are never applied automatically — apply them per clip from the inspector or in bulk via "Apply Suggested Ratings to Unrated Clips", which never overwrites a rating a person set.

### Sony a7R V workflow

SlateBox detects Sony-style media layouts and surfaces `PRIVATE/M4ROOT/CLIP` as the primary video folder. Proxy inclusion can be enabled for workflows that need Sony proxy files from adjacent proxy folders. Strong SHA256 verification is available, but fast size verification is the default for large 4K60 10-bit footage because hashing source and destination can be slow.

### Safety rules

- SlateBox copies by default; it does not delete camera originals.
- Export-to-edit actions should copy files and avoid overwriting existing filenames.
- Production metadata is saved to the SlateBox project JSON, not written into MP4 or MOV media files.
- Keep cards and drives connected until ingest completion and verification are finished.

### Metadata behavior

Project and clip metadata are stored in `.SlateBox-project.json`. Clip metadata includes cull status, production tags, people, location, scene, shot type, notes, favorites, B-roll, sermon, interview, and social candidate flags. Automatic tags are rule-based and local only.

### Export behavior

SlateBox includes menu actions for Clip Report CSV, Keep List CSV, and Project Metadata JSON. CSV reports include filenames, cull status, duration, file size, resolution, frame rate, codec, tags, notes, source path, and destination path.

### Known limitations

- The logo is a polished SwiftUI placeholder and not a final brand asset.
- Copy Keeps to Edit Folder is planned but not fully implemented in this pass.
- Local analysis is rule-based only; no cloud AI and no heavy Core ML model are included.
- Folder delete removes the folder assignment from the project metadata only; it does not delete media files.

## 2026 SlateBox workflow update

### Camera card workflows

- **Sony cards:** SlateBox detects `PRIVATE/M4ROOT/CLIP` and scans full-resolution clips there. Sony proxy files in `PRIVATE/M4ROOT/SUB` remain skipped by default unless proxy ingest is enabled.
- **Canon/DCF cards:** SlateBox detects a root `DCIM` folder, recursively scans Canon/DCF video folders, and imports video-oriented formats such as `.MP4`, `.MOV`, and `.CRM`. Photo and sidecar formats such as `.JPG`, `.CR3`, and `.THM` are ignored for this pass.
- **Generic folders:** If no known camera structure is detected, SlateBox performs a recursive video scan.

### Folder structure options

- **Flat:** Copies detected videos directly into the project or shoot folder. This is the default for camera-card style ingest.
- **Preserve Source Structure:** Keeps the source-relative folder layout inside the SlateBox project.

### Transfer controls and destinations

- Streaming copies now use `.SlateBox-partial` temporary files and only move into place after the file is fully copied.
- Ingest can be paused and resumed between copy chunks without destructive SD card operations.
- The ingest sheet includes a primary destination plus optional Backup 1 and Backup 2 destination fields.
- Backups are intended to be copied from the verified primary destination so the SD card is read once.
- Mounted NAS folders are treated like normal folders. NAS transfers may be slower, and disconnects should be retried after the share is available again.
- **Cloud-synced folder support** means local folders managed by iCloud Drive, Dropbox, Google Drive, or OneDrive. SlateBox does not upload directly to cloud providers in this pass.

### Keyboard shortcuts

- Space: open preview for the selected clip, or play/pause while preview is focused.
- Escape: close preview.
- Right Arrow / Left Arrow: select next or previous visible clip.
- 5: Keep.
- 3: Maybe.
- 1: Reject.
- 0: Unrated.

### Local offline analysis

SlateBox includes a local analysis foundation with Off, Fast, Balanced, and Detailed modes. Analysis runs only on copied destination files, stores results in project JSON, and can populate smart folders and inspector fields for:

- Possibly Out of Focus
- Faces, Group Shots, Close Faces, Low Face Visibility
- Possibly Shaky, Stable Clips, High Motion
- Dark Clips, Bright Clips, Low Contrast
- Failed Analysis

### Privacy

All analysis is designed to run offline with Apple APIs. SlateBox does not upload frames, face data, or clip metadata to cloud AI services. Face features are for organization only; SlateBox does not automatically identify people by real name.

### Known limitations

- `.CRM` files may copy and verify even when AVFoundation preview is unavailable on the current Mac.
- Local analysis scores are advisory and may flag intentionally soft, dark, or moving footage.
- Direct Dropbox, Google Drive, and OneDrive upload APIs are not implemented; use their local synced folders instead.

### Local placeholder app icons

Codex does not commit generated icon PNGs because binary files are not supported by the patch system. To generate local placeholder app icons on a development Mac, run:

```bash
python3 Scripts/generate_app_icon.py
```

The generated PNG files are ignored by git at `ClipVault/Assets.xcassets/AppIcon.appiconset/*.png`. The SwiftUI in-app logo remains available without generated binary assets.

## Session-based ingest review

SlateBox now reviews source media as detected sessions before copying. Sessions are grouped by recording/creation date with a 90-minute gap split so a day with multiple shoots can be selected in chunks. Session cards show the date/time range, clip count, total size, camera/card type (Sony, Canon/DCF, or Generic), and a lightweight thumbnail strip placeholder before ingest starts.

The ingest panel keeps rename off by default. When enabled, files are copied as `[Project Name]-[YYYY][MM][DD]-[Sequence].EXT`, and the original filename remains stored in `.SlateBox-project.json`. Start Ingest stays disabled until there is a destination, project name, and at least one selected clip/session.

Parallel options include thumbnail generation during ingest, local analysis after ingest, and contact-sheet preparation toggles. Analysis remains local-only and runs only after files are safely copied into the destination project.

## Local analysis details and disclaimers

Local analysis uses Apple APIs only: AVFoundation samples a small number of frames, Core Graphics/Core Image-style pixel metrics estimate focus, exposure, contrast, white balance, and motion, and Vision detects face rectangles. Fast mode samples 3 frames, Balanced samples 5 frames or roughly every 10 seconds, and Detailed samples every 2–5 seconds with a cap; SlateBox never analyzes every frame.

- **Focus:** sharpness is estimated from luminance edge energy. “Possibly Out of Focus” is advisory and can be wrong for intentional soft focus, background shots, haze, or low-detail scenes.
- **Exposure/contrast:** brightness, dark pixels, bright pixels, and contrast spread are estimated from sampled frames. Tags such as Dark Clip, Bright Clip, Low Contrast, and Balanced Exposure are organizational hints only.
- **White balance:** SlateBox stores an approximate Kelvin-style value when camera metadata is unavailable. Estimated values are shown as “Approx.” with confidence because true camera white balance is often not present in MP4/MOV metadata.
- **Faces and privacy:** Vision detects face presence, approximate counts, close faces, group shots, low visibility, and an anonymous unique-face appearance estimate. SlateBox does not identify people, does not assign names, and does not upload face data.
- **Stability:** motion and shake are estimated from sampled frame differences. “Possibly Shaky” is advisory and may flag intentional handheld movement or fast pans.

## App icon generation

Binary PNG icon files are intentionally ignored so text-only changes can build in source control. To generate local Xcode app icons on a Mac, run:

```bash
python3 Scripts/generate_app_icon.py
# or
make icons
```

The script writes `ClipVault/Assets.xcassets/AppIcon.appiconset/icon_16.png` through `icon_1024.png` plus `Contents.json`. Run `make icons`, then use **Product → Clean Build Folder** in Xcode and rebuild SlateBox. Generated PNGs are ignored by git.

## Recent SlateBox Improvements

### Ingest session and folder selection
- The New Ingest screen now treats each `IngestSession.selected` value as the selection source of truth. The copy pipeline receives only the clips selected through session or individual file checkboxes.
- Session cards include clear checkboxes, whole-card click toggling, selected/partial badges, accent borders, selected backgrounds, and selected count/size review totals.
- Selection controls include Select All, Clear Selection, Select Today, Select New Only, Select by Date, and Reload.
- The ingest setup panel exposes handling choices for already imported media: skip already copied, retry failed only, or include all with safe rename.

### Individual clip selection
- Session cards can expand to show individual source files with checkboxes.
- Selecting or clearing individual clips updates the session card state, selected clip count, and total selected size.
- Partial selections are called out explicitly so ingesting one session no longer accidentally copies every scanned clip.

### Library layout and partial libraries
- The library uses a fixed compact sidebar, a flexible primary clip grid, and a bounded/collapsible inspector so the grid remains the main workspace after ingest.
- A toolbar control shows or hides the inspector, and the preference is saved in user defaults.
- Partial ingest libraries show a compact top banner with Resume Ingest, Retry Failed, and Reveal Project Folder actions.
- Pending clips remain in the project metadata as non-destructive records and are not previewed unless a destination file exists.

### Shot-time sorting and manual production time
- Clips now store `capturedAt`, `shotStartTime`, `manualShotTime`, and `shotTimeSource` in `.SlateBox-project.json` metadata.
- Library sorting includes Ingest Order, Shot Time, Filename, Created Date, Modified Date, Duration, File Size, Cull Status, Rating/Keep Status, and Camera Type, plus Ascending/Descending order.
- Shot Time uses a manual override first when present, then camera/media metadata, file creation, file modified date, and available fallback metadata.
- The inspector shows Shot Time and source and allows setting, using current time for, or clearing a Manual Shot Time override.

### macOS 26 design and Apple Intelligence preparation
- Design changes continue to use native SwiftUI/AppKit materials, accent-aware highlights, compact banners, and readable inspector cards with fallbacks that do not raise the deployment target.
- macOS 26-only future hooks are guarded with `#available(macOS 26.0, *)`.
- A local-only `LocalSuggestionService` architecture has been added with a rule-based implementation and a guarded `FoundationModelSuggestionService` placeholder. SlateBox does not use cloud AI, does not upload media, and does not require Foundation Models to build.

### Compatibility and safety
- SlateBox continues to use Apple APIs only and does not require FFmpeg.
- Source media and SD-card contents are never modified or deleted.
- App metadata remains in `.SlateBox-project.json`; SlateBox does not write metadata into MP4/MOV files by default.

## Project JSON Compatibility

SlateBox stores project metadata in `.SlateBox-project.json` files inside project folders. The project JSON now includes a `schemaVersion` field so future migrations can be detected and handled safely while preserving existing media and metadata.

Older project files that do not include `schemaVersion` should remain openable with backward-compatible defaults for newer ingest, session, and metadata fields. Codable unit tests protect project and clip JSON from breaking changes, including partial or canceled ingests that must remain reopenable.
