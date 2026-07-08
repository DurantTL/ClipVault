# ClipVault Agent Instructions

ClipVault is a native macOS SwiftUI app for safe video ingest, culling, preview, organization, and metadata.

## Core Safety Rules

Never break these:

- Never delete source files.
- Never modify source SD card files.
- Never format SD cards.
- Never overwrite destination files.
- Always use safe duplicate naming.
- Copy first.
- Verify second.
- Preview/cull only from copied destination files.
- Metadata belongs in `.clipvault-project.json` or sidecars, not inside original MP4/MOV files by default.
- Partial/canceled ingests must remain reopenable.

## Build Rule

Before claiming work is complete, the app must build:

```bash
xcodebuild \
  -project ClipVault.xcodeproj \
  -scheme ClipVault \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
