import Foundation

enum CullStatus: String, Codable, CaseIterable, Identifiable {
  case unrated, keep, maybe, reject
  var id: String { rawValue }
  var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

  /// Star ratings that agree with this status. Rating and status coexist:
  /// status stays the fast three-way cull, rating adds finer 0–5 control.
  var consistentRatings: ClosedRange<Int> {
    switch self {
    case .unrated: return 0...0
    case .reject: return 1...1
    case .maybe: return 2...3
    case .keep: return 4...5
    }
  }

  var defaultRating: Int {
    switch self {
    case .unrated: return 0
    case .reject: return 1
    case .maybe: return 3
    case .keep: return 4
    }
  }

  static func status(forRating rating: Int) -> CullStatus {
    switch rating {
    case ..<1: return .unrated
    case 1: return .reject
    case 2, 3: return .maybe
    default: return .keep
    }
  }
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
