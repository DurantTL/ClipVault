# SlateBox Agent Instructions

SlateBox (repository directory `ClipVault`) is a native macOS SwiftUI app for safe video ingest, culling, preview, organization, and metadata.

## Core Safety Rules

Never break these:

- Never delete source files.
- Never modify source SD card files.
- Never format SD cards.
- Never overwrite destination files.
- Never write thumbnails to source cards.
- Always use safe duplicate naming.
- Copy first.
- Verify second.
- Preview/cull only from copied destination files.
- New Ingest may generate temporary read-only thumbnails from source media for identification only.
- Full playback preview, culling, rating, metadata editing, analysis, aliases, and export must use copied project files only.
- Library thumbnails are generated from copied project files only.
- Metadata belongs in `.clipvault-project.json` or sidecars, not inside original MP4/MOV files by default.
- Partial/canceled ingests must remain reopenable.

## Rating and Cull Status Rules

- Clips carry both a 0–5 `rating` and a coarse `cullStatus`; keep them in sync through `Clip.applyRating` / `Clip.applyCullStatus` — never set either field directly in new code.
- Mapping: 0 → Unrated, 1 → Reject, 2–3 → Maybe, 4–5 → Keep. Setting a status only adjusts the rating when they disagree.
- Old project JSON without a rating must keep decoding; the rating is derived from the saved cull status.
- Analysis suggestions (suggested rating, Top Pick / Social Pick tags) are opt-in only — never auto-apply them over a user's rating.
- Exports (edit-folder copies, reports) read copied project media only, copy instead of move, and never overwrite (safe `_1`, `_2` names).

## Source Permission Rules

The app is sandboxed. Any change to source selection must preserve this behavior:

- Removable volumes (as reported by macOS) are read through the `com.apple.security.files.removable-media.read-only` entitlement and must never show SlateBox's own picker.
- Non-removable detected sources (external SSDs, fixed card readers, network volumes) get a one-time `NSOpenPanel` grant, persisted as a security-scoped bookmark in `UserDefaults` keyed by volume path.
- A source granted during the current session must stay granted: `NewIngestViewModel` caches granted URLs by source ID and keeps their security scope active until deinit. Swapping between sources must never re-prompt for an already granted source.
- Security-scoped bookmarks can only be created or refreshed while access to the URL is active. Never create a bookmark from a resolved URL before starting access, and never overwrite a stored bookmark with a failed creation.
- Re-prompt only when a bookmark no longer covers the mounted volume path (for example, the card remounted at a new path).

## Build Rule

Before claiming work is complete, the app must build:

```bash
xcodebuild \
  -project SlateBox.xcodeproj \
  -scheme SlateBox \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
