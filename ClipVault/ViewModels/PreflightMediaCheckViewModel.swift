import Foundation

@MainActor final class PreflightMediaCheckViewModel: ObservableObject {
  @Published var results: [UUID: PreflightClipResult] = [:]
  @Published var isRunning = false
  @Published var message = "Run Preflight to check the destination, recent projects, and configured backups."
  @Published var lastCheckedAt: Date?

  let service = PreflightMediaCheckService()

  var hasResults: Bool { !results.isEmpty }
  var summary: PreflightSummary { PreflightSummary(results: results) }

  func result(for clipID: UUID) -> PreflightClipResult? {
    results[clipID]
  }

  func reset() {
    results = [:]
    lastCheckedAt = nil
    message = "Run Preflight to check the destination, recent projects, and configured backups."
  }
}
