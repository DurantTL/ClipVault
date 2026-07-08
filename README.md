# ClipVault

ClipVault is a native macOS SwiftUI app for safe video ingest, preview, culling, and folder sorting. It copies video files from an SD card or source folder to a destination project folder, verifies the copies, generates thumbnails, and lets users review and sort the copied media without touching the original source.

## Build

Open `ClipVault.xcodeproj` in Xcode 15 or newer on macOS 14+, select the `ClipVault` scheme, and run. The app uses only Apple frameworks: SwiftUI, AVFoundation, AVKit, Foundation/FileManager, UniformTypeIdentifiers, CryptoKit, and AppKit where macOS-specific APIs are needed.

## Ingest workflow

1. Click **New Ingest**.
2. Choose a source folder such as an SD card or camera-card copy.
3. Choose a destination folder such as an SSD or mounted NAS folder.
4. Name the project. The default is date-based.
5. ClipVault scans Sony cards by using `PRIVATE/M4ROOT/CLIP` when present.
6. Proxy files in Sony `PRIVATE/M4ROOT/SUB` are skipped by default unless **Include Proxy Files** is enabled. Non-Sony folders continue to scan recursively.
7. Click **Start Copy**. ClipVault streams each file in chunks, updates progress during large copies, verifies the result, then generates metadata and a thumbnail only for successfully copied and verified clips.
8. The library opens so clips can be previewed, marked Keep/Maybe/Reject, revealed in Finder, and moved into custom folders.

## Safety behavior

- ClipVault never deletes source files.
- ClipVault never formats or erases cards.
- ClipVault never modifies original media.
- ClipVault never overwrites destination files; conflicts receive `_1`, `_2`, etc.
- Ingest copy uses security-scoped access for selected source, destination, and project folders so SD cards, external SSDs, and mounted NAS locations continue working after the user grants access.
- If ingest is canceled during a large file copy, copied files are left in place, source files are untouched, and the project is marked incomplete.
- If copy or verification fails for one clip, ClipVault records the error on that clip and continues with the remaining clips.
- Failed clips do not run metadata extraction or thumbnail generation.
- Thumbnail failures do not invalidate a copied and verified clip; the UI falls back to a generic video icon.
- Culling only changes project metadata.
- Physical sorting only moves copied files inside the destination project folder, and undo restores clip path metadata.

## Verification

The default verification mode is **Fast size check**, which confirms the copied file size without rereading the SD card more than necessary. **Strong SHA256** remains available in Settings for users who want a safer byte-level hash comparison, but it is slower for large Sony a7R V 4K60 4:2:2 10-bit files because it reads both the source media and copied destination media.

## Project files and recent projects

Each project folder contains a hidden `.clipvault-project.json` metadata file. **Open Existing Project** accepts either the project folder or the hidden JSON file. Recent projects are stored as project metadata-file paths and display a friendly error if an external SSD or NAS volume is disconnected or unavailable.

## Sony a7R V focus

The MVP is focused on Sony a7R V/XAVC-style workflows: `PRIVATE/M4ROOT/CLIP` prioritization, proxy exclusion by default, optional proxy inclusion from `PRIVATE/M4ROOT/SUB`, chunked copy with cancel support, fast verification by default, and AVFoundation-based metadata/thumbnail extraction without transcoding, LUTs, or color transforms.

## Known limitations

- No cloud sync, AI analysis, duplicate detection, editing timeline, NLE export, SD formatting, permanent deletion, or multi-user collaboration.
- Preview, metadata, and thumbnail support depends on AVFoundation codecs available on the user's Mac.
- The first version generates one cached thumbnail per clip, not filmstrips/contact sheets.
- Recent projects can only reopen automatically while the project folder, external SSD, or NAS mount is available at the expected location or resolvable by its bookmark.
