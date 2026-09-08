# Privacy Policy

**Product:** SlateBox (working name; public brand TBD)  
**Company:** Durant Logic  
**Effective date:** TBD (publish when the hosted URL goes live)

This policy describes how SlateBox handles data on your Mac. SlateBox is designed as a **local-first** video ingest, verify, cull, and handoff app. It does not require a Durant Logic account and does not upload your media to Durant Logic for analysis or storage.

> **App Store Connect note:** This markdown is the in-repo source of truth. A stable `https://` Privacy Policy URL (for example on the Durant Logic site or GitHub Pages) must be published before App Store submission. Until then, treat this document as the draft policy.

## Summary

- Processing happens **on your Mac** using Apple frameworks (SwiftUI, AVFoundation, Vision, and related system APIs).
- SlateBox does **not** use cloud AI and does **not** upload frames, face data, or clip metadata to cloud AI services.
- Face detection is for **organization only** (presence, approximate counts, anonymous geometry). SlateBox does **not** identify people or assign real names.
- There is **no telemetry** or analytics by default.
- Source / camera-card media is **never** deleted, formatted, or modified by SlateBox.

## What SlateBox processes locally

When you use SlateBox, it may read and write data on volumes and folders **you select**, including:

- Source folders or camera cards you grant access to for ingest
- Destination project folders (SSD, NAS, or other folders you choose)
- Optional backup destination folders you configure

Typical local operations include copying video files, verifying copies, generating thumbnails and metadata from **copied** files, local technical analysis (focus / exposure / stability / face rectangles), and saving cull ratings, tags, and notes in the project file.

## What we do not do

- We do not upload your video frames, audio, face data, or project metadata to Durant Logic servers for AI analysis.
- We do not sell your media or personal information.
- We do not require you to create an account to use the core offline workflow.
- We do not write thumbnails or analysis caches onto source camera cards.
- We do not identify individuals by name from face detection.

## Data stored on your Mac

SlateBox stores project and cache data locally, including:

| Location | Purpose |
|----------|---------|
| `.clipvault-project.json` inside each project folder | Project and clip metadata (ratings, tags, notes, paths, analysis results) |
| `.clipvault-cache/` inside the project folder | Local caches such as library thumbnails from copied media |
| `.clipvault-partial` temporary files during copy | Incomplete copies until a file finishes transferring |
| `~/Library/Caches/ClipVault/` | Local preview / ingest identification caches |

These on-disk names are permanent format identifiers and may keep the legacy `clipvault` spelling even if the public product name changes.

Security-scoped bookmarks may be saved so previously granted folders (external drives, NAS mounts, and similar) can be reopened without re-prompting every launch.

## Face data

Local analysis may use Apple Vision to detect face **rectangles** and related organizational signals (for example presence, approximate count, close faces, group shots). This is intended to help you cull and organize footage.

- Face features are **not** used to identify people by real name.
- Face data is **not** uploaded to Durant Logic or third-party cloud AI services by SlateBox.
- Results are stored in the local project metadata you keep on your disks.

## Diagnostics and support

The in-app **Help → Save Diagnostics Report…** action writes a **local** plain-text report (app version, system profile, settings, recent project paths). The report stays on your Mac unless **you** choose to share it with support.

See also [Support](support.md).

## Third-party services

SlateBox’s core workflow is offline. If future optional features contact the network (for example a manual “Check for Updates” against GitHub Releases), those will be described here before they ship. Today there is no Durant Logic cloud backend for ingest or analysis.

Folders managed by iCloud Drive, Dropbox, Google Drive, or OneDrive are treated as ordinary local folders when you point SlateBox at them; SlateBox does not implement direct provider upload APIs in the current product.

## Children’s privacy

SlateBox is intended for professional and prosumer media workflows, not for children under 13. We do not knowingly collect personal information from children.

## Changes to this policy

When this policy changes, we will update the effective date and the hosted Privacy Policy URL used in App Store Connect. Material changes should be called out in product release notes when practical.

## Contact

**Durant Logic**  
Privacy questions: see [Support](support.md) (email / contact URL TBD before App Store submission).

GitHub project: [DurantTL/ClipVault](https://github.com/DurantTL/ClipVault)
