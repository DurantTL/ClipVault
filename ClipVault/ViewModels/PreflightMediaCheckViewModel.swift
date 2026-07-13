import Foundation

@MainActor final class PreflightMediaCheckViewModel: ObservableObject {
  @Published private(set) var results: [UUID: PreflightClipResult] = [:]
  @Published private(set) var isRunning = false
  @Published private(set) var message = "Run Preflight to check existing media."
  @Published private(set) var lastCheckedAt: Date?

  private let service = PreflightMediaCheckService()

  var hasResults: Bool { !results.isEmpty }
  var summary: PreflightSummary { PreflightSummary(results: results) }

  func result(for clipID: UUID) -> PreflightClipResult? {
    results[clipID]
  }

  func reset() {
    results = [:]
    lastCheckedAt = nil
    message = "Run Preflight to check existing media."
  }
}
