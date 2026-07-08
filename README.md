# ClipVault

ClipVault is a native macOS SwiftUI app for safe video ingest, preview, culling, and folder sorting. It copies video files from an SD card or source folder to a destination project folder, verifies the copies, generates thumbnails, and lets users review and sort the copied media without touching the original source.

## Build

Open `ClipVault.xcodeproj` in Xcode 15 or newer on macOS 14+, select the `ClipVault` scheme, and run. The app uses only Apple frameworks: SwiftUI, AVFoundation, AVKit, Foundation/FileManager, UniformTypeIdentifiers, CryptoKit, and AppKit where macOS-specific APIs are needed.

## Ingest workflow

1. Click **New Ingest**.
2. Choose a source folder such as an SD card or camera-card copy.
3. Choose a destination folder such as an SSD or mounted NAS folder.
4. Name the project. The default is date-based.
5. ClipVault scans recursively for supported videos and prioritizes Sony `PRIVATE/M4ROOT/CLIP` folders when present.
6. Proxy files in Sony `PRIVATE/M4ROOT/SUB` are skipped by default unless **Include Proxy Files** is enabled.
7. Click **Start Copy**. ClipVault copies first, verifies second, then generates thumbnails and metadata.
8. The library opens so clips can be previewed, marked Keep/Maybe/Reject, revealed in Finder, and moved into custom folders.

## Safety rules

- ClipVault never deletes source files.
- ClipVault never formats or erases cards.
- ClipVault never overwrites destination files; conflicts receive `_1`, `_2`, etc.
- Culling only changes project metadata.
- Physical sorting only moves copied files inside the destination project folder.
- Files remain ingestible and sortable even if AVFoundation cannot preview or thumbnail them on a Mac.

## Sony a7R V focus

The MVP is optimized for Sony a7R V/XAVC-style workflows: recursive card scanning, `PRIVATE/M4ROOT/CLIP` prioritization, proxy exclusion by default, safe copy/verify behavior, and AVFoundation-based preview without transcoding, LUTs, or color transforms.

## Known limitations

- No cloud sync, AI analysis, duplicate detection, editing timeline, NLE export, SD formatting, permanent deletion, or multi-user collaboration.
- Preview and thumbnail support depends on AVFoundation codecs available on the user's Mac.
- The first version generates one cached thumbnail per clip, not filmstrips/contact sheets.
