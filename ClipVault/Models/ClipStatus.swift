import Foundation

enum CullStatus: String, Codable, CaseIterable, Identifiable {
  case unrated, keep, maybe, reject
  var id: String { rawValue }
  var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

enum VerificationStatus: String, Codable, CaseIterable {
  case pending, copied, verified, failed
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
