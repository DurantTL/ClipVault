# ClipVault Overnight Review — 2026-09-12

Full overnight audit of the ClipVault project: repo code review, issues triage, roadmap, market research, and the brand-name decision.

> The review referred to three companion files (`repo-review.md`, `market-research.md`, `name-evaluation.md`). They are **not** in the repository; only this summary is. The trademark and domain findings below were checked against a USPTO-data mirror and are not a substitute for an attorney clearance search.

## Status update — 2026-09-28

Work merged after this review (PRs [#109](https://github.com/DurantTL/ClipVault/pull/109)–[#116](https://github.com/DurantTL/ClipVault/pull/116)) changed several findings below. Checked against `main`:

| Finding | Status |
|---|---|
| Path traversal via unsanitized `projectName` | **Fixed** (#109, #110, #112): single validation entry point, containment asserted on ingest, resume, backups, aliases, moves, exports, MHL output and thumbnail storage. Rename tokens (#77) must use the same validation when built. |
| `PlayerViewModel` `@MainActor` + debug print | **Fixed** for the preview prints (gated behind the `previewDebugLogging` default). Other diagnostic `print` calls remain (`ThumbnailService`, `IngestPreviewThumbnailService`, `Log.info`). |
| #91 per-destination copy/verify state | **Done** (#113–#115): per-destination records, resume retries only incomplete backups, per-destination UI, Retry Backups. |
| #92 full-content verification default | **Partly done, decision changed.** The owner chose to **keep Fast size check as the default** (the review recommended SHA256). #116 makes the guarantee explicit (card labels, CSV method column, MHL lists only SHA256-verified copies per destination). Hash-on-read and measured throughput are still open. |
| #56 view-model tests | **Done** for `LibraryViewModel` (#111). |
| Release workflow invalid (`secrets` in step `if`) | **Fixed** (#111); unverified until a `v*` tag is pushed. |
| **Destination-vs-source guard** | **Still open.** `chooseDestination()` does not reject a folder on the source card. |
| **Exports use plain `copyItem`** (no verification) | **Still open** (`ClipExportService`). |
| **`MHLReportService.relativePath` falls back to the filename** | **Still open.** |
| **Stray `.trust-phase0-mcp-probe.txt`** | **Still open** (file exists at the repo root). |
| Undocumented `network.client` entitlement | **Still open** (used by the update check). |
| Hand-rolled `Clip` Codable (#54) | **Still open**, though legacy-decode and destination-record tests were added. |
| Licensing/purchase tracking issue | **Not filed.** |
| Naming: README still says SlateBox | **Not changed.** Naming is a product decision. |

## 1. Repo assessment

**Architecture.** Clean, Apple-frameworks-only (SwiftUI, AVFoundation/AVKit, Vision, CryptoKit, AppKit — no FFmpeg, no third-party deps). Layers are sensible: Models (~80-field `Clip`, `ClipVaultProject`, cull/rating enums), Services (the safety-critical core: streaming chunked copy with pause/resume, SHA256 verification, card-layout scanning, duplicate preflight, sandbox-safe bookmarks, offline Vision analysis, MHL reports), and decomposed ViewModels (the 982-line god object is gone). Data flow is disciplined: sources are read-only throughout, destinations append-only with safe naming, and production metadata lives in project JSON/sidecars, never inside MP4/MOV files.

**Completeness: strong beta, not a launch candidate.** The core loop genuinely works end-to-end (scan → copy → verify → cull → export), and the July→September progress is large. But the repo's own bar — "no paid trust claim until issues #90/#91/#92" — is unmet, hardware recovery validation (#55) is manual-only, and the differentiator (Phase 3, the menu-bar card checkmark) has zero code written. Honest self-assessment: great for beta testers, not ready to sell.

**Code quality.** Many prior issues were verified fixed (data races, bookmark overwrites, thumbnail retention, shortcut hijacking). New findings from this audit:

- **Path-traversal hole** — `projectName` isn't sanitized before being appended to the destination path (`../../X` escapes it). Fix under #90 with a containment test.
- **No destination-vs-source guard** — a user can pick a folder on the camera card as the destination, writing partials and project JSON onto the card. This is the closest thing to a live violation of the "never touch source" rule. Cheap fix: block with an explanatory error.
- **Export is ingest's weak sibling** — editor handoff copies use plain `FileManager.copyItem` with no verification. Route exports through the streaming copy path.
- **`MHLReportService.relativePath`** silently falls back to a wrong filename when prefix-matching fails — it should throw, since this is a proof artifact.
- **Housekeeping:** delete stray `.trust-phase0-mcp-probe.txt`; document the `network.client` entitlement; mark `PlayerViewModel` `@MainActor` and remove a debug print.
- **Still-open debt:** hand-rolled `Clip` Codable across three parallel lists (#54 — the most likely source of a silent schema bug), zero view-model tests (#56).

**Test posture.** 71 test methods across 13 files, genuinely healthy (no skips/stubs), CI runs them on build and release. Gaps remain in view-model logic, `ProjectStore` internals, and `LocalAnalysisService`.

## 2. Issues triage (45 open, 0 open PRs at the time of the review)

**The critical path — do these before anything paid:**

| # | Issue | Why it's the gate |
|---|---|---|
| 90 | Destination-path containment + project-name validation | Fixes the traversal hole; asserts all writes stay inside the destination |
| 91 | Independent per-destination copy/verify state | Phase 3's "safe to remove" checkmark cannot be computed honestly without it |
| 92 | Full-content (hash-on-read) verification as default | Single highest-leverage trust item; unblocks the wedge, proof artifacts, every "verified" claim |
| 55 | Hardware recovery validation (SSD/NAS/revoke/resume) | Manual-only today; you can't sell trust without proving recovery |

**The trust wedge (Phase 3):**

| # | Issue | Note |
|---|---|---|
| 93 | Menu-bar card status + "Eject All Safe Cards" | The differentiator — but zero code exists; gated on #91/#92 |
| 94 | Physical card lifecycle | Same gate |

Also worth prioritizing: wire the already-tested `MHLReportService` into the export UI (#67 — low effort), first-class post-ingest verification artifacts (#78), PDF transfer reports (#95), and file a new licensing/purchase tracking issue — the roadmap assumes one-time pricing but nothing in the repo plans a license key, trial, or purchase flow.

Notable closed work: ViewModel decomposition (#52), manual update check (#66). The #83 master tracker covers the long tail (FCPXML/Resolve handoff, proxy generation, contact sheets, on-device transcription, archive re-verification, iOS companion — all later).

## 3. Roadmap feedback

The ordering is coherent and the Phase 0 gates correctly block the trust wedge. What's missing:

- **Licensing/purchase flow** — no issue, no code, no mention anywhere. File the tracking issue now; decide Mac App Store vs. direct sale.
- **Notarization proof** — the workflow supports it but the secrets are unverified; do the #62 dry-run tag release before launch day.
- **Ship #92 before #93/#94** — enforce the ordering in the #83 tracker; starting the wedge before per-destination state is computable would be dishonest UI.
- App Store privacy policy URL is correctly flagged as required before submission (`docs/privacy.md`).
- The "reliability/hardware matrix" (#104) and project-format spec (#102) are tracked — good; the matrix doubles as go-to-market proof.

## 4. Market analysis

The lane is real and empty: no product bundles checksum-verified ingest + culling + editor handoff under ~$100, and none targets churches or volunteer-run media teams by name.

- **Pro offload tools** (OffShoot $169, ShotPut Pro $149, Silverstack rental-only) verify checksums but have no culling/preview at all and are priced/built for paid DITs.
- **Culling/organize tools** are dead or wrong-shaped: Kyno (the closest historical analog) is in maintenance-only mode at Signiant with no new features; Photo Mechanic ($149/yr–$299) is photo-first; NeoFinder/CatDV are dated.
- **Tusk** (launched Aug 2026, $49→$79, Mac-native, BLAKE3 checksums, solo dev, PetaPixel coverage) is the live threat: same price band, same Silicon story — but it does no culling, no ratings, no editor handoff. It validates the market while leaving ClipVault's half of it untouched. If Tusk adds culling, the moat narrows.
- **DaVinci Resolve's free Clone Tool** caps willingness to pay; ClipVault must sell time saved and fear removed, not features. The Resolve handoff export is the right move — meet church teams where they already live (free Resolve) rather than competing with it.
- **Subscription resentment:** Photo Mechanic's community backlash and OffShoot's switch to perpetual pricing both say this audience resents subscriptions.

**Recommended positioning & pricing:**

- $59–$79 one-time perpetual (Mac App Store or direct); optional team/church license $149–$199 for 5 seats. No subscription — ever.
- Pitch: "The verified ingest and culling tool your volunteers can actually use — built for Sunday mornings, not DITs." (i.e., "Photo Mechanic for video," now that Kyno died.)
- Differentiators to ship first: Keep/Maybe/Reject + DaVinci-ready handoff folders, church-specific naming presets (`2026-09-13_Sunday-AM_Cam1`), duplicate detection against recycled cards, and offline AI quality scoring — literally no competitor offers offline analysis.
- Consider a 501(c)(3) ministry discount as a brand-building wedge; the 13,000-member Iowa-Missouri Conference is itself a distribution channel.

## 5. Name recommendation: TakeHarbor — not Cullect

Recommend **TakeHarbor**. It is the only candidate that is simultaneously legally clear, domain-viable, free of homophone traps, and conceptually aligned ("bring your footage into a safe harbor" = the trust wedge).

**Why not Cullect** (despite the great cull+collect wordplay):

- It's pronounced identically to "collect" — every spoken mention, every App Store search, every autocorrect will leak to the wrong spelling. It fails the "say it over a walkie-talkie" test.
- **Trademark:** two LIVE federal "COLLECT" marks in software classes (Class 42, registered Mar 2025 — Nikola Labs; Class 9, registered Jul 2024 — Solesavy US). A Class 9 "Cullect" filing would very likely draw a §2(d) refusal. (Verified via USPTO-data mirror; not a substitute for a full attorney clearance search.)
- WeTransfer's "Collect" is a live app with 35M+ downloads in the Photo & Video category, updated Jan 2026 — it would swallow all spoken/typed discovery.
- cullect.com is taken since 2006 with all locks set (not a drop candidate); cullect.app is available, but the .app can't fix the trademark/autocorrect problems.

**Why not SlateBox:** an active SaaS company (Slatebox LLC, since ~2016) sells software under that exact name in the same classes. It's currently the README's working title — that should be corrected. **Why not ClipVault:** clipvault.app is taken, a historic broadcast service used the name, and it's generic/descriptive (weak trademark).

**Next steps on the name:**

1. Check who registered takeharbor.com (2025-06-26 — possibly already yours); takeharbor.app is verified available.
2. Run a professional attorney clearance search on TakeHarbor.
3. Test "TakeHarbor: Video Ingest" in App Store Connect per the existing `NAMING.md` strategy.
4. Update the README working title/disclaimer; the rename itself is a one-file `AppBrand.swift` change.
5. Keep the Cullect spirit as a feature label ("Cull & Collect" for the culling mode) rather than the master brand.

## 6. Prioritized next steps

**This week (trust gates — nothing paid until these land):**

1. Fix #90 including the project-name traversal hole, with a containment test. *(Done — see status update.)*
2. Add the destination-vs-source guard to New Ingest (cheapest new safety rule). *(Open.)*
3. Ship #92 (hash-on-read full-content default) — unlocks everything downstream. *(Partly done; default kept as fast.)*
4. File the licensing/purchase tracking issue and decide App Store vs. direct.

**Next (the wedge):**

1. #91 per-destination state *(done)* → then #93/#94 menu-bar card checkmark (the differentiator).
2. Wire `MHLReportService` into export UI (#67); route exports through streaming copy.
3. #62 dry-run release (signing/notarization/DMG proof) and #55 hardware recovery validation.

**GTM, in parallel:**

1. Decide the name (recommend TakeHarbor) and update the README/disclaimer.
2. Settle pricing ($59–$79 one-time; $149–$199 5-seat church tier) and the 30-day trial story.
3. Start dogfooding with real Sunday-morning workflows — the 13,000-member conference is the beta fleet.
