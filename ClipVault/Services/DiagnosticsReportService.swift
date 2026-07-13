import AppKit
import Foundation

/// Builds a local plain-text diagnostics report for support. Everything stays
/// on the user's machine — the report is only written where the user chooses
/// via a save panel, and nothing is ever uploaded.
struct DiagnosticsReportService {
  func report(now: Date = Date(), defaults: UserDefaults = .standard) -> String {
    let bundle = Bundle.main
    let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    let buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    let profile = SystemPerformanceProfile.current()
    let recentProjects = defaults.stringArray(forKey: "recentProjects") ?? []

    var lines: [String] = []
    lines.append("\(AppBrand.appName) Diagnostics Report")
    lines.append("Generated: \(ISO8601DateFormatter().string(from: now))")
    lines.append("")
    lines.append("[App]")
    lines.append("Version: \(appVersion) (\(buildNumber))")
    lines.append("Bundle ID: \(bundle.bundleIdentifier ?? "unknown")")
    lines.append("")
    lines.append("[System]")
    lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
    lines.append("Apple Silicon: \(profile.isAppleSilicon)")
    lines.append("Processor class: \(profile.processorClass.rawValue)")
    lines.append("Physical memory: \(profile.physicalMemoryGB) GB")
    lines.append("Supports heavy analysis: \(profile.supportsHeavyAnalysis)")
    lines.append("Recommended thumbnail concurrency: \(profile.recommendedThumbnailConcurrency)")
    lines.append("Recommended analysis concurrency: \(profile.recommendedAnalysisConcurrency)")
    lines.append("")
    lines.append("[Settings]")
    lines.append("Verification mode: \(defaults.string(forKey: "verificationMode") ?? "fast")")
    lines.append("Performance mode: \(defaults.string(forKey: "performanceMode") ?? PerformanceMode.automatic.rawValue)")
    lines.append("Thumbnail quality: \(defaults.string(forKey: "thumbnailQuality") ?? "balanced")")
    lines.append("Local analysis mode: \(defaults.string(forKey: "localAnalysisMode") ?? "Off")")
    lines.append("Include proxy files: \(defaults.bool(forKey: "includeProxyFiles"))")
    lines.append("Preserve source structure: \(defaults.bool(forKey: "preserveSourceStructure"))")
    lines.append("Generate thumbnails during ingest: \(defaults.bool(forKey: "generateThumbnailsDuringIngest"))")
    lines.append("Backup transfer mode: \(defaults.string(forKey: "backupTransferMode") ?? "Primary only")")
    lines.append("")
    lines.append("[Recent Projects] (\(recentProjects.count))")
    if recentProjects.isEmpty {
      lines.append("none")
    } else {
      for (index, path) in recentProjects.enumerated() {
        let reachable = FileManager.default.fileExists(atPath: path)
        lines.append("\(index + 1). \(path) — \(reachable ? "reachable" : "not mounted")")
      }
    }
    lines.append("")
    return lines.joined(separator: "\n")
  }

  @MainActor func saveViaPanel() {
    let panel = NSSavePanel()
    panel.title = "Save Diagnostics Report"
    panel.message = "The report stays on this Mac. Attach it manually if you are asking for help."
    panel.nameFieldStringValue = "\(AppBrand.appName)-Diagnostics.txt"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    try? report().write(to: url, atomically: true, encoding: .utf8)
  }
}
