import Foundation

enum CullStatus: String, Codable, CaseIterable, Identifiable {
  case unrated, keep, maybe, reject
  var id: String { rawValue }
  var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

enum VerificationStatus: String, Codable, CaseIterable {
  case pending, copied, verified, failed
}

enum ProjectIngestStatus: String, Codable, CaseIterable {
  case notStarted
  case inProgress
  case paused
  case canceled
  case incomplete
  case complete
  case failed

  var label: String {
    switch self {
    case .notStarted: return "Not Started"
    case .inProgress: return "In Progress"
    case .paused: return "Paused"
    case .canceled: return "Canceled"
    case .incomplete: return "Incomplete"
    case .complete: return "Complete"
    case .failed: return "Failed"
    }
  }

  var canResume: Bool {
    self == .canceled ||
      self == .incomplete ||
      self == .paused ||
      self == .failed
  }
}

enum ClipCopyStatus: String, Codable, CaseIterable {
  case pending
  case copying
  case copied
  case failed
  case skipped
}

enum ThumbnailStatus: String, Codable, CaseIterable {
  case pending
  case generating
  case generated
  case failed
  case notNeeded
}

enum VerificationMode: String, Codable, CaseIterable, Identifiable {
  case fast, strong
  var id: String { rawValue }
  var label: String { self == .fast ? "Fast size check" : "Strong SHA256" }
}

enum ThumbnailQuality: String, Codable, CaseIterable, Identifiable {
  case fast, balanced, best
  var id: String { rawValue }
  var maxPixelSize: Int { self == .fast ? 360 : (self == .balanced ? 720 : 1280) }
}
