# SlateBox / ClipVault — Full Project Review (2026-07-13)

Scope: every tracked file in the repository — app source (`ClipVault/`), tests (`ClipVaultTests/`), Xcode project (`SlateBox.xcodeproj`), CI workflows, docs, scripts, and entitlements. This review reports findings only; no code was changed.

## Executive summary

The codebase is in good shape where it matters most. The safety contract declared in `AGENTS.md` — copy first, verify second, never overwrite, never touch source media, ratings only through `Clip.applyRating`/`applyCullStatus` — is upheld everywhere in production code, the sandbox entitlements are minimal and match the documentation exactly, and the test suite is real and healthy (9 files, ~52 tests, no skips or stubs).

The most significant problems are: one genuine data race in the ingest cancel/pause path, one violation of the project's own bookmark-persistence rule, a user-facing feature (Rename Folder) that cannot work, six dead placeholder files left behind by a tooling limitation, documentation that describes an already-shipped feature (Preflight Media Check) as future work, and a Release build configuration that may not be compiling with optimizations.

Severity legend: **High** — incorrect behavior or undefined behavior reachable in normal use. **Medium** — degraded behavior, latent hazard, or misleading project state. **Low** — hygiene, duplication, style.

---

## 1. Correctness and safety findings

### 1.1 (High) Data race on ingest cancel/pause flags

`ClipVault/Services/IngestService.swift:9-14` declares plain mutable state on a non-isolated class:

```swift
var cancelled = false
var paused = false
func cancel() { cancelled = true }
```

These are **written on the main actor** by the ingest UI (`ClipVault/Views/NewIngestView.swift:310, 365-367` call `vm.ingestService.cancel()/pause()/resume()`) and **read on a background thread** inside `StreamingCopyService`'s `Task.detached` copy loop via the `isCancelled`/`isPaused` closures (`ClipVault/Services/StreamingCopyService.swift:88-89`, wired at `IngestService.swift:21-22`). Unsynchronized cross-thread read/write of non-atomic storage is undefined behavior in Swift. It will usually "work," but cancellation is exactly the path exercised when something is already going wrong during an ingest.

Suggested fix: make the flags actor-isolated, guard them with `OSAllocatedUnfairLock`/`NSLock`, or use `ManagedAtomic<Bool>`. Related: because `IngestService` is a shared non-isolated object held by a `@MainActor` view model, nothing structurally prevents overlapping `ingest`/`resume` runs from stomping the shared `copyService.isCancelled`/`isPaused` closures.

### 1.2 (High) Backup pickers can wipe a stored bookmark — violates AGENTS.md:39

`ClipVault/ViewModels/NewIngestViewModel.swift:301` and `:307`:

```swift
settings.backupDestination1BookmarkBase64 =
  (try? bookmarks.bookmark(for: url))?.base64EncodedString() ?? ""
```

If bookmark creation fails, the previously persisted bookmark is overwritten with an empty string. `AGENTS.md:39` says: "never overwrite a stored bookmark with a failed creation." Every other bookmark write site honors this (e.g. `NewIngestViewModel.swift:128, 184-186` only store non-nil results). Real-world risk is low (the URL comes from a fresh `NSOpenPanel` grant, so creation normally succeeds), but the `?? ""` fallback is the wrong default and this is the one place in the codebase that contradicts the rule.

Suggested fix: only assign when creation succeeds; leave the stored value untouched on failure.

### 1.3 (High) "Rename Folder" is a no-op — the feature cannot work

`ClipVault/Views/SidebarView.swift:51-54`:

```swift
Button("Rename Folder") {
  renameFolderName = folder
  vm.renameFolder(folder, to: renameFolderName)  // renames folder → itself
}
```

The button assigns the current name into `renameFolderName` and immediately calls `renameFolder(folder, to: folder)`. There is no text-entry prompt anywhere in the flow, so a user can never actually rename a folder. The `@State private var renameFolderName` (`SidebarView.swift:6`) exists only to serve this dead path.

Suggested fix: present an alert/sheet with a `TextField` bound to `renameFolderName` and call `renameFolder` from its confirm action.

### 1.4 (Medium) Preview-thumbnail tasks retain the ingest view model past window close

`ClipVault/ViewModels/NewIngestViewModel.swift:490-520`: the per-clip preview-thumbnail `Task` captures `self` strongly and is stored in `previewThumbnailTasks[clip.id]` (`:520`) — a VM → task → VM cycle that only breaks when each task finishes. `deinit` (`:531-534`) does **not** call `cancelPreviewThumbnailWork()`, so after the ingest window closes, the view model — including the security-scoped access URLs it retains in `activeAccessURLsByPath` — stays alive until every in-flight thumbnail task drains. Every other background task in the codebase uses `[weak self]` (e.g. `NewIngestViewModel.swift:341`, `LibraryViewModel.swift:557, 633, 699`); this one is the inconsistency.

Suggested fix: capture `[weak self]` in the thumbnail task and cancel outstanding tasks in `deinit`.

### 1.5 (Medium) Bare-key menu shortcuts can hijack text-field typing

`ClipVault/ClipVaultApp.swift:26-47` binds menu key equivalents for space, `0`–`5`, and the arrow keys with `modifiers: []`. AppKit dispatches menu key equivalents before the responder chain, and unlike the in-grid `KeyboardShortcutCatcher` — which bails when a text view is first responder (`ClipVault/Views/ClipGridView.swift:86`) — the menu items have no text-editing guard. The inspector and ingest panels are full of `TextField`s (`ClipInspectorView.swift:71-94`, `NewIngestView.swift:195-215`); typing a digit into Tags or a project name can be intercepted and re-routed to `setRating(...)`. Flagged as *plausible* — verify interactively on a build.

Suggested fix: guard the menu actions on `NSApp.keyWindow?.firstResponder is NSTextView`, or use `.disabled(...)` driven by focus state.

### 1.6 (Medium) File reads without security-scoped access on external/NAS volumes

- `ClipVault/Services/LocalAnalysisService.swift:313-338` reads the clip's `currentPath` for frame extraction without a `withAccess` wrap, unlike `MetadataService.enrich` (`MetadataService.swift:9`) which wraps correctly. On sandboxed external/NAS project volumes, analysis can silently fail and clips get "Failed Analysis" for no visible reason.
- The preflight scan (`ClipVault/Services/SourceScanner.swift:265-315`) enumerates destination/backup roots with no security scope and returns `[]` on failure, so already-imported files can be misclassified as "New." Not destructive — ingest still uses safe `_1`/`_2` naming — but it weakens the duplicate guard the feature exists to provide.

### 1.7 (Medium) Same-named automatic tags mean different things on different code paths

Tag derivation is duplicated with inconsistent thresholds between `MetadataService.automaticTags` (`MetadataService.swift:60-70`) and `LocalAnalysisService.tags` (`LocalAnalysisService.swift:266-311`):

| Tag | MetadataService | LocalAnalysisService |
|---|---|---|
| Large File | > 4 GB | ≥ 5 GB |
| Short Clip | < 15 s | < 30 s |
| Long Clip | > 10 min | ≥ 5 min |

A clip can gain or lose these tags depending on whether analysis has run. Suggested fix: extract one shared threshold table.

### 1.8 (Low) Ingest progress counts can drift

`ClipVault/Services/IngestService.swift:341-348` (`refreshCounts`): a clip counts as *copied* (copyStatus `.copied` or verified) or *pending* (`.pending`/`.copying`), but a `.failed` clip lands in neither bucket, so `copied + pending + failed` need not equal the selected total. Cosmetic — the progress numbers can look inconsistent during a partially failed ingest.

---

## 2. Safety-rule compliance — what's working (verified)

- **Copy first, verify second:** `IngestService.swift:96` (copy) then `:109` (verify); resume path always verifies `.strong` (`:261`).
- **Never overwrite destinations:** existence checks before copy and again before the final `moveItem` (`StreamingCopyService.swift:37-39, 104-107`); `SafeFilename.uniqueURL` `_1`/`_2` naming used for project folders, clips, backups, exports, and moves (`Formatters.swift:16-47`).
- **Never delete/modify source:** every `removeItem` in the codebase targets only temp/cache artifacts — `.clipvault-partial` + manifest (`StreamingCopyService.swift:60-64, 108`), preview cache (`IngestPreviewThumbnailService.swift:119`), cache folders (`AppSettings.swift:277`). None touch source paths.
- **Thumbnails never written to source cards:** cache directories resolve only to internal caches, the destination project, or a user-chosen folder (`AppSettings.swift:103-224`).
- **Rating invariant:** all production writes go through `applyRating`/`applyCullStatus` (`Clip.swift:404-416`; `LibraryViewModel.swift:169, 174, 184`); suggestions are opt-in and never overwrite user ratings.
- **Bookmark session rules:** refresh only while the scope is active (`NewIngestViewModel.swift:177-187`); session grants cached, never re-prompted (`:195-213`); re-prompt only on remount-path mismatch (`:215-226`). (Exception: finding 1.2.)
- **Entitlements** (`ClipVault/ClipVault.entitlements`): sandbox + `files.user-selected.read-write` + `files.removable-media.read-only` + `files.bookmarks.app-scope` — minimal, no over-broad grants, and exactly matching the behavior documented in README/AGENTS.md.
- **Partial ingests reopenable:** project JSON is written before any bytes move (`IngestService.swift:67`) and re-saved after every clip (`:162`); cancellation marks the project resumable.

---

## 3. Dead code and structure

### 3.1 (Medium) Six orphaned placeholder files

These are 3-line comment stubs, referenced by nothing in `project.pbxproj` (zero `Preflight` matches), left behind because the authoring tool could not delete files:

- `ClipVault/Services/PreflightMediaCheckService.swift`
- `ClipVault/ViewModels/PreflightMediaCheckViewModel.swift`
- `ClipVault/ViewModels/PreflightMediaCheckViewModel+Run.swift`
- `ClipVault/ViewModels/PreflightMediaCheckViewModel+Projects.swift`
- `ClipVault/Views/PreflightMediaCheckViews.swift`
- `ClipVaultTests/PreflightMediaCheckTests.swift`

They are harmless to the build but should simply be deleted. No coverage was lost in the consolidation: the preflight tests live and run in `ClipVaultTests/SourceScannerTests.swift:193-330`.

### 3.2 (Medium) Preflight code is mis-homed

The real implementations were consolidated into files whose names no longer describe them: `SourceScanner.swift` (547 lines) now contains the scanner **plus** the `PreflightMediaCheckService` actor (`:176`), all preflight value types, and even the `@MainActor` `PreflightMediaCheckViewModel` (`:369-547`); the preflight SwiftUI cards live inside `IngestProgressView.swift:32-148`. A view model in a `Services/` scanner file will surprise every future reader. Suggested fix: re-split into properly named files (now that direct file operations are available, the original file layout can be restored).

### 3.3 (Low) God objects

- `LibraryViewModel.swift` — 982 lines: selection, filtering, sorting, thumbnails, analysis, export, aliasing, folder ops, CSV generation (`:895-981`), security-scoped access, resume-ingest. The CSV subsystem and `BatchMetadataEdit` (`:56-91`) are clean extraction candidates. (`ROADMAP.md:73` already flags this.)
- `SettingsView.swift` — 910 lines in a single view file.
- `NewIngestView.swift` (679) / `NewIngestViewModel.swift` (651) are borderline.

### 3.4 (Medium) `Clip.swift` hand-rolled Codable is a silent-persistence hazard

`Clip.swift` (421 lines) maintains ~80 stored properties across three parallel ~100-line lists: `CodingKeys`, `init(from:)` (`:196-298`), and `encode(to:)` (`:300-398`). A new property that misses one of the three lists silently fails to persist — precisely the class of bug the project's schema-compatibility tests exist to prevent, but the tests only cover known fields. Suggested fix: rely on synthesized Codable plus a small custom-decode shim for the legacy-rating migration, or group new metadata into sub-structs.

### 3.5 (Low) Duplication

- `thumbnailSeconds(for:)` byte-identical in `ThumbnailService.swift:104-112` and `IngestPreviewThumbnailService.swift:125-133`.
- Keyboard handling exists in three places (menu commands `ClipVaultApp.swift:26-47`, grid catcher `ClipGridView.swift:85-121`, preview catcher `PlayerPreviewView.swift:50-67`); menu equivalents dispatch first, making much of the grid catcher unreachable. Behavior is currently consistent but fragile.
- Pairs of buttons wired to identical actions: "Resume Ingest"/"Retry Failed" both call `resumeIngest()` (`LibraryView.swift:257-258`); "Analyze"/"Reanalyze This Clip" both call `analyzeSelectedClip()` (`ClipInspectorView.swift:121-122`); three buttons all call `runPreflight()` (`NewIngestView.swift:128, 149, 247`).

### 3.6 (Low) `HomeViewModel.summaries` re-reads disk on every render

`HomeViewModel.swift:27-29`: `summaries` is a computed property that JSON-decodes every recent project from disk, and `HomeView` reads it several times per render (`HomeView.swift:12-65`). Worse, `RecentProjectSummary.id = UUID()` (`HomeViewModel.swift:5`) mints a new identity on each recompute, forcing `ForEach` to rebuild all rows every pass. Suggested fix: load once (async) into a `@Published` array with stable IDs (e.g. the project path).

### 3.7 (Low) Focus-stealing shortcut catcher

`KeyboardShortcutCatcher.swift:10, 16`: both `makeNSView` and `updateNSView` re-grab first responder on every re-render, which can yank focus out of an inspector `TextField` mid-edit, and the grid + preview catchers compete when both are alive.

### 3.8 (Low) `PlayerViewModel` is the only non-`@MainActor` view model

`PlayerViewModel.swift:4` mutates `@Published` state with no actor isolation. All current callers are main-thread, so it works today, but it's a latent gap next to its AV-callback-adjacent role.

---

## 4. Tests

**Healthy:** 9 files, ~52 test methods, no `XCTSkip`, no empty bodies, no sleep-based timing. Copy/verify tests are properly async. Coverage of the safety-critical copy → verify → export path is genuinely good (`StreamingCopyServiceTests`, `VerificationServiceTests`, `SourceScannerTests` incl. preflight, `ClipExportServiceTests`, `RatingAndSuggestionTests`, Codable schema tests).

**Gaps (by value):**

1. **`FileMoveService` — untested.** It performs physical moves of copied files with undo (safety-relevant per `AGENTS.md:14`). Highest-value missing test.
2. `IngestService` orchestration (per-clip failure isolation, cancel → resumable project) has no direct test.
3. `ProjectStore` persistence (only the Codable models are covered), `MetadataService`, `AliasService` internals, `SecurityScopedBookmarkManager`, `LocalAnalysisService`.
4. Zero view-model tests — notable for the 982-line `LibraryViewModel`.

---

## 5. Build configuration and CI

- **(Medium) Release optimization unverified:** neither Release config sets `SWIFT_OPTIMIZATION_LEVEL` (`project.pbxproj:150, 152`). In a hand-authored pbxproj without the Xcode template defaults, Swift may compile Release at `-Onone`. Verify a release build's settings (`xcodebuild -showBuildSettings -configuration Release | grep SWIFT_OPT`) and set `-O` explicitly.
- **(Medium) No `SWIFT_STRICT_CONCURRENCY`:** the code leans on actors and `@MainActor`, but with `SWIFT_VERSION = 5.0` and no strict-concurrency flag, none of it is compiler-checked — which is how finding 1.1 survives. Enabling `SWIFT_STRICT_CONCURRENCY = targeted` (then `complete`) would surface these at compile time.
- **(Low) Floating CI runners:** `runs-on: macos-latest` in both workflows (`build.yml:11`, `release.yml:25`) means Xcode/macOS can shift underneath releases; pin to `macos-15` (or similar).
- **(Low) Workflow polish:** no `concurrency:` cancel-in-progress block; no dependency caching; release secrets are hoisted to job-level `env:` (`release.yml:26-31`) instead of per-step scoping — blast radius is small (only first-party `actions/checkout@v4` runs), but step-scoping is cleaner. Signing/notarization gating on secret presence (`:76, 91, 113`) is done correctly, and the unsigned-DMG fallback works as documented.
- **(Low) Asset catalog broken at rest:** `AppIcon.appiconset/Contents.json` references 10 PNGs that are git-ignored; a fresh clone won't build cleanly in Xcode until `make icons` runs. CI handles it (`build.yml:22-26`) and README documents it, but the committed state points at missing files. Consider committing placeholder PNGs or removing the filenames from `Contents.json` until generated.
- Good: tests run in both workflows; `ENABLE_TESTABILITY` is Debug-only; entitlements wired via `CODE_SIGN_ENTITLEMENTS`; `arm64`-only is intentional and documented.

---

## 6. Documentation accuracy

- **(Medium) Roadmap/reality inversion:** `ROADMAP.md:90-92` lists **Preflight Media Check / already-imported detection** as future Phase 3 priority #1 ("the biggest real-workflow gap") — but the feature shipped in PR #42 (`f993dad`) and lives in `SourceScanner.swift` + `IngestProgressView.swift` with passing tests. The Shipped section (`:52-63`) omits it, `CHANGELOG.md` `[Unreleased]` omits it, and `README.md:101` still claims "no … duplicate detection," which the feature contradicts.
- **(Low) AGENTS.md still calls the product ClipVault** (`AGENTS.md:1, 3, 36`) — every other doc was renamed to SlateBox.
- **(Low) Hardcoded brand string:** `LibraryView.swift:272` embeds the literal `"SlateBox"` in an `NSOpenPanel` message instead of `AppBrand.appName`, breaking the single-source-of-truth rename contract in `AppBrand.swift:4-11` — a real liability given `NAMING.md:35-36` anticipates another possible rename. Console log prefixes also still say "ClipVault" (`Formatters.swift:53`, `LibraryViewModel.swift:339`, `PlayerViewModel.swift:52`).
- **(Low) Wrong icon filenames in README:** `README.md:278` says the script writes `icon_16.png`–`icon_1024.png`; it actually writes `icon_16x16_1x.png`–`icon_512x512_2x.png` (`Scripts/generate_app_icon.py:51-53`).
- Accurate and consistent: `TESTING.md`'s coverage list matches the real test files; `NAMING.md`'s frozen on-disk identifiers match `AppBrand.swift:20-24`; release instructions match `release.yml`; the intentional `clipvault` on-disk spelling is well documented and correct.

---

## 7. Repository hygiene

- `.gitignore` (3 lines) only covers generated icon PNGs — add `.DS_Store`, `build/` (release workflow writes there), `DerivedData/`, `xcuserdata/`.
- Stray zero-byte `.gitkeep` at the repo root does nothing — remove.
- `project.pbxproj` is hand-authored with fabricated sequential object IDs; functional, but expect wholesale churn the first time Xcode's GUI rewrites it.

---

## 8. Prioritized recommendations

1. Fix the ingest cancel/pause data race (1.1) — small, mechanical, protects the most safety-critical path.
2. Fix the `?? ""` bookmark overwrite (1.2) and the Rename Folder no-op (1.3).
3. Delete the six orphaned placeholder files (3.1) and re-home the preflight code into properly named files (3.2).
4. Correct the docs: move Preflight Media Check to Shipped, fix `README.md:101`, add it to the changelog; rename ClipVault→SlateBox in AGENTS.md; fix the icon-filename claim (§6).
5. Set `SWIFT_OPTIMIZATION_LEVEL = -O` for Release and adopt `SWIFT_STRICT_CONCURRENCY = targeted` (§5).
6. Add `FileMoveService` tests, then `IngestService` orchestration tests (§4).
7. Round out hygiene: weak-self + deinit-cancel for preview thumbnails (1.4), text-field guard on menu shortcuts (1.5), security-scope wraps in analysis/preflight (1.6), unified tag thresholds (1.7), broadened `.gitignore`, pinned CI runners.
