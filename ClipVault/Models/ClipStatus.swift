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

/// Which copy of a clip a record describes. The primary is the project folder;
/// backups are the optional Backup 1 / Backup 2 destinations.
enum DestinationRole: String, Codable, CaseIterable, Equatable {
  case primary, backup1, backup2

  var label: String {
    switch self {
    case .primary: return "Primary"
    case .backup1: return "Backup 1"
    case .backup2: return "Backup 2"
    }
  }
}

/// How a copy was verified. `sizeCheck` must never be presented as checksum
/// verification.
enum VerificationMethod: String, Codable, Equatable {
  case none, sizeCheck, sha256

  init(_ mode: VerificationMode) { self = mode == .strong ? .sha256 : .sizeCheck }
}

/// Copy and verification state of one clip on one destination, so a backup
/// failure can never mask a verified primary and a verified primary never
/// implies a verified backup.
struct DestinationCopyRecord: Codable, Equatable, Identifiable {
  var role: DestinationRole
  /// Root folder of the destination this copy lives under. Empty when unknown
  /// (records derived from projects saved before per-destination tracking).
  var destinationPath: String = ""
  var copyState: ClipCopyStatus = .pending
  var verificationState: VerificationStatus = .pending
  var verificationMethod: VerificationMethod = .none
  /// Lowercase hex SHA256; only set when the copy was verified with `.sha256`.
  var checksum: String?
  var byteSize: Int64 = 0
  var updatedAt: Date?
  var errorMessage: String?

  var id: String { role.rawValue }
  var isVerified: Bool { verificationState == .verified }

  init(role: DestinationRole) { self.role = role }

  enum CodingKeys: String, CodingKey {
    case role, destinationPath, copyState, verificationState, verificationMethod
    case checksum, byteSize, updatedAt, errorMessage
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    role = try c.decode(DestinationRole.self, forKey: .role)
    destinationPath = try c.decodeIfPresent(String.self, forKey: .destinationPath) ?? ""
    copyState = try c.decodeIfPresent(ClipCopyStatus.self, forKey: .copyState) ?? .pending
    verificationState = try c.decodeIfPresent(VerificationStatus.self, forKey: .verificationState) ?? .pending
    verificationMethod = try c.decodeIfPresent(VerificationMethod.self, forKey: .verificationMethod) ?? .none
    checksum = try c.decodeIfPresent(String.self, forKey: .checksum)
    byteSize = try c.decodeIfPresent(Int64.self, forKey: .byteSize) ?? 0
    updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
  }
}

extension VerificationMethod {
  /// User-facing wording. A size comparison is never described as a checksum.
  var label: String {
    switch self {
    case .none: return "not verified"
    case .sizeCheck: return "size check"
    case .sha256: return "SHA256"
    }
  }
}

extension DestinationCopyRecord {
  /// One-line status for the inspector, e.g. "Verified (SHA256)".
  var statusText: String {
    switch verificationState {
    case .verified: return "Verified (\(verificationMethod.label))"
    case .failed: return errorMessage.map { "Failed — \($0)" } ?? "Failed"
    case .copied: return "Copied, not yet verified"
    case .pending: return copyState == .copying ? "Copying…" : "Pending"
    }
  }
}

extension Clip {
  /// Compact badge text when the clip has more than one destination, e.g.
  /// "2/3 copies verified". `nil` when only the primary is tracked, in which
  /// case the single verification badge is enough.
  var destinationBadgeText: String? {
    guard destinationRecords.count > 1 else { return nil }
    let verified = verifiedDestinationCount
    let total = destinationRecords.count
    return verified == total ? "\(total) copies verified" : "\(verified)/\(total) copies verified"
  }

  /// How the primary copy was verified, in words that never call a size
  /// comparison a checksum: "SHA256", "size check", or "not verified".
  var primaryVerificationMethodLabel: String {
    guard verificationStatus == .verified else { return VerificationMethod.none.label }
    if let record = destinationRecord(for: .primary), record.isVerified {
      return record.verificationMethod.label
    }
    return (checksum ?? "").isEmpty ? VerificationMethod.sizeCheck.label : VerificationMethod.sha256.label
  }

  /// True when any tracked destination failed or is not yet verified.
  var hasDestinationAttention: Bool {
    destinationRecords.contains { !$0.isVerified }
  }
}

extension ClipVaultProject {
  /// Clips with a verified primary that still lack a verified copy on one of
  /// the configured backup destinations.
  func clipsMissingBackups(configured: Set<DestinationRole>) -> Int {
    guard !configured.isEmpty else { return 0 }
    return clips.filter { clip in
      clip.verificationStatus == .verified
        && configured.contains { clip.destinationRecord(for: $0)?.isVerified != true }
    }.count
  }
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
