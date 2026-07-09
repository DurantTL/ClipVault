import Foundation

enum BackgroundWorkKind: String, Sendable {
  case ingestCopy
  case verification
  case ingestPreviewThumbnail
  case libraryThumbnail
  case contactSheet
  case localAnalysis
  case export
  case cloudTransfer
}

struct BackgroundWorkStatus: Identifiable, Sendable {
  let id: UUID
  let kind: BackgroundWorkKind
  let label: String
  let startedAt: Date
}

actor BackgroundWorkCoordinator {
  static let shared = BackgroundWorkCoordinator()

  private var active: [UUID: BackgroundWorkStatus] = [:]
  private var limits: [BackgroundWorkKind: Int]

  init(profile: SystemPerformanceProfile = .current()) {
    limits = [
      .ingestCopy: 1,
      .verification: 1,
      .ingestPreviewThumbnail: profile.recommendedThumbnailConcurrency,
      .libraryThumbnail: profile.recommendedThumbnailConcurrency,
      .contactSheet: max(1, profile.recommendedThumbnailConcurrency - 1),
      .localAnalysis: profile.recommendedAnalysisConcurrency,
      .export: 1,
      .cloudTransfer: 2
    ]
  }

  func statuses() -> [BackgroundWorkStatus] {
    active.values.sorted { $0.startedAt < $1.startedAt }
  }

  func begin(kind: BackgroundWorkKind, label: String) async -> UUID {
    while active.values.filter({ $0.kind == kind }).count >= (limits[kind] ?? 1) {
      try? await Task.sleep(nanoseconds: 50_000_000)
      if Task.isCancelled { break }
    }
    let id = UUID()
    active[id] = BackgroundWorkStatus(id: id, kind: kind, label: label, startedAt: Date())
    return id
  }

  func finish(_ id: UUID) {
    active.removeValue(forKey: id)
  }
}
