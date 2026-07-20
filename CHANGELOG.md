# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/). Releases are cut by pushing a
`vX.Y.Z` tag, which builds, packages, and publishes a DMG via GitHub Actions.

## [Unreleased]

### Added
- Destination-capacity preflight with blocking for known insufficient space,
  low-space warnings, and a non-blocking advisory when a NAS cannot report capacity.
- Actionable recovery messages for disk-full, disconnected-volume,
  permission-loss, and read-only failures during ingest, resume, backup,
  project save, and report export.
- Preflight Media Check before ingest: source clips are compared by file
  identity against the destination, configured backups, and recent projects,
  with per-clip statuses and skip-already-copied selection.
- First-launch onboarding walkthrough (drives → protected copy → project
  library → cull → export), re-openable from Help → Welcome.
- Keyboard shortcut cheat sheet under Help → Keyboard Shortcuts.
- Help → Save Diagnostics Report… writes a local plain-text support report
  (app/system/settings/recent projects). Nothing is uploaded.
- Tag-triggered release workflow: Release build, optional Developer ID
  signing and notarization when secrets are configured, DMG packaging, and a
  published GitHub Release.

### Changed
- All user-visible brand strings flow through `AppBrand`; hidden on-disk
  format identifiers are frozen regardless of future product renames.
- Settings toggles without an implementation are hidden until their features
  exist.

### Fixed
- Failed ingests now keep `ingestIncomplete` set, and canceling a resumed
  ingest preserves the Canceled/resumable project state instead of overwriting
  it as a generic incomplete result.
- Project-save, report-export, and undo failures are no longer silently
  discarded; the library presents an error banner and allows failed project
  saves to be retried.
- Backup destinations now resolve through their persisted security-scoped
  bookmarks, backup failures no longer cancel later backup attempts, and a
  cancel during backup correctly cancels the ingest.
- App no longer hangs on launch when a configured folder or recent project
  lives on a disconnected network drive or external volume. Security-scoped
  bookmarks now resolve without mounting (and off the main thread at launch),
  so unavailable volumes are skipped and re-resolved on demand instead of
  stalling startup.
- Stale security-scoped bookmarks now self-heal. When a file server or volume
  is renamed, resolving its bookmark reports it stale; project-folder and
  storage/backup bookmarks are now re-created from the resolved location and
  persisted, so a renamed server keeps opening instead of failing every launch.
- Documentation now matches the real on-disk file names
  (`.clipvault-project.json`, `.clipvault-cache`, `.clipvault-partial`).

## Pre-release history

Before the changelog was introduced, development shipped: guided ingest with
Sony/Canon/generic card detection, streaming chunked copy with pause/resume
and reopenable partial ingests, fast and SHA256 verification, backup
destinations, library culling with 0–5 star ratings and keyboard review,
multi-select and bulk metadata, local rule-based and Vision analysis with
suggested ratings, aliases, edit-folder export with safe duplicate naming,
CSV/JSON reports, editor handoff (Finder, DaVinci Resolve, Final Cut Pro),
camera/card metadata, Apple Silicon performance profiles, and automated
safety-pipeline tests.
