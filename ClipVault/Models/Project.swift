import Foundation

struct ClipVaultProject: Identifiable, Codable {
  var id = UUID()
  var name: String
  var createdAt = Date()
  var lastOpenedAt: Date?
  var sourceBookmarkData: Data?
  var destinationBookmarkData: Data?
  var projectFolderBookmarkData: Data?
  var projectFolderPath: String
  var ingestIncomplete: Bool = false
  var ingestStatus: ProjectIngestStatus = .notStarted
  var totalSelectedClips: Int = 0
  var copiedClipCount: Int = 0
  var verifiedClipCount: Int = 0
  var failedClipCount: Int = 0
  var pendingClipCount: Int = 0
  var lastIngestDate: Date?
  var canResumeIngest: Bool = false
  var sourceSessions: [IngestSession] = []
  var selectedSessionIDs: [UUID] = []
  var customFolders: [String] = ["Sermon", "B-Roll", "Social Media", "Archive", "Review Later"]
  var clips: [Clip] = []

  var projectTitle: String = ""
  var productionName: String = ""
  var clientOrOrganization: String = ""
  var eventName: String = ""
  var eventDate: Date?
  var location: String = ""
  var cameraOperator: String = ""
  var cameraModel: String = ""
  var notes: String = ""
  var defaultTags: [String] = []

  init(
    id: UUID = UUID(),
    name: String,
    createdAt: Date = Date(),
    lastOpenedAt: Date? = nil,
    sourceBookmarkData: Data? = nil,
    destinationBookmarkData: Data? = nil,
    projectFolderBookmarkData: Data? = nil,
    projectFolderPath: String,
    ingestIncomplete: Bool = false,
    ingestStatus: ProjectIngestStatus = .notStarted,
    totalSelectedClips: Int = 0,
    copiedClipCount: Int = 0,
    verifiedClipCount: Int = 0,
    failedClipCount: Int = 0,
    pendingClipCount: Int = 0,
    lastIngestDate: Date? = nil,
    canResumeIngest: Bool = false,
    sourceSessions: [IngestSession] = [],
    selectedSessionIDs: [UUID] = [],
    customFolders: [String] = ["Sermon", "B-Roll", "Social Media", "Archive", "Review Later"],
    clips: [Clip] = []
  ) {
    self.id = id
    self.name = name
    self.createdAt = createdAt
    self.lastOpenedAt = lastOpenedAt
    self.sourceBookmarkData = sourceBookmarkData
    self.destinationBookmarkData = destinationBookmarkData
    self.projectFolderBookmarkData = projectFolderBookmarkData
    self.projectFolderPath = projectFolderPath
    self.ingestIncomplete = ingestIncomplete
    self.ingestStatus = ingestStatus
    self.totalSelectedClips = totalSelectedClips
    self.copiedClipCount = copiedClipCount
    self.verifiedClipCount = verifiedClipCount
    self.failedClipCount = failedClipCount
    self.pendingClipCount = pendingClipCount
    self.lastIngestDate = lastIngestDate
    self.canResumeIngest = canResumeIngest
    self.sourceSessions = sourceSessions
    self.selectedSessionIDs = selectedSessionIDs
    self.customFolders = customFolders
    self.clips = clips
  }

  enum CodingKeys: String, CodingKey {
    case id, name, createdAt, lastOpenedAt, sourceBookmarkData, destinationBookmarkData
    case projectFolderBookmarkData, projectFolderPath, ingestIncomplete, ingestStatus
    case totalSelectedClips, copiedClipCount, verifiedClipCount, failedClipCount, pendingClipCount
    case lastIngestDate, canResumeIngest, sourceSessions, selectedSessionIDs, customFolders, clips
    case projectTitle, productionName, clientOrOrganization, eventName, eventDate, location
    case cameraOperator, cameraModel, notes, defaultTags
    case isComplete, complete, isInProgress, wasCanceled
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    name = try c.decode(String.self, forKey: .name)
    createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    lastOpenedAt = try c.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
    sourceBookmarkData = try c.decodeIfPresent(Data.self, forKey: .sourceBookmarkData)
    destinationBookmarkData = try c.decodeIfPresent(Data.self, forKey: .destinationBookmarkData)
    projectFolderBookmarkData = try c.decodeIfPresent(Data.self, forKey: .projectFolderBookmarkData)
    projectFolderPath = try c.decode(String.self, forKey: .projectFolderPath)
    ingestIncomplete = try c.decodeIfPresent(Bool.self, forKey: .ingestIncomplete) ?? false
    clips = try c.decodeIfPresent([Clip].self, forKey: .clips) ?? []
    let decodedIngestStatus = try? c.decodeIfPresent(
      ProjectIngestStatus.self,
      forKey: .ingestStatus
    )
    let legacyIsComplete = try c.decodeIfPresent(Bool.self, forKey: .isComplete)
    let legacyComplete = try c.decodeIfPresent(Bool.self, forKey: .complete)
    let legacyIsInProgress = try c.decodeIfPresent(Bool.self, forKey: .isInProgress)
    let legacyWasCanceled = try c.decodeIfPresent(Bool.self, forKey: .wasCanceled)
    let legacyCanResumeIngest = try c.decodeIfPresent(Bool.self, forKey: .canResumeIngest)
    let inferredStatus = Self.inferIngestStatus(
      from: clips,
      ingestIncomplete: ingestIncomplete
    )

    if let decodedIngestStatus {
      ingestStatus = decodedIngestStatus
    } else if legacyWasCanceled == true {
      ingestStatus = .canceled
    } else if legacyIsInProgress == true {
      ingestStatus = .inProgress
    } else if legacyIsComplete == true || legacyComplete == true {
      ingestStatus = .complete
    } else if legacyCanResumeIngest == true || ingestIncomplete {
      ingestStatus = .incomplete
    } else {
      ingestStatus = inferredStatus
    }
    totalSelectedClips = try c.decodeIfPresent(Int.self, forKey: .totalSelectedClips) ?? clips.count
    copiedClipCount = try c.decodeIfPresent(Int.self, forKey: .copiedClipCount) ?? clips.filter { $0.copyStatus == .copied || $0.verificationStatus == .verified }.count
    verifiedClipCount = try c.decodeIfPresent(Int.self, forKey: .verifiedClipCount) ?? clips.filter { $0.verificationStatus == .verified }.count
    failedClipCount = try c.decodeIfPresent(Int.self, forKey: .failedClipCount) ?? clips.filter { $0.copyStatus == .failed || $0.verificationStatus == .failed }.count
    pendingClipCount = try c.decodeIfPresent(Int.self, forKey: .pendingClipCount) ?? max(0, totalSelectedClips - copiedClipCount - failedClipCount)
    lastIngestDate = try c.decodeIfPresent(Date.self, forKey: .lastIngestDate)
    canResumeIngest = legacyCanResumeIngest ?? ingestStatus.canResume
    sourceSessions = try c.decodeIfPresent([IngestSession].self, forKey: .sourceSessions) ?? []
    selectedSessionIDs = try c.decodeIfPresent([UUID].self, forKey: .selectedSessionIDs) ?? []
    customFolders = try c.decodeIfPresent([String].self, forKey: .customFolders) ?? ["Sermon", "B-Roll", "Social Media", "Archive", "Review Later"]
    projectTitle = try c.decodeIfPresent(String.self, forKey: .projectTitle) ?? ""
    productionName = try c.decodeIfPresent(String.self, forKey: .productionName) ?? ""
    clientOrOrganization = try c.decodeIfPresent(String.self, forKey: .clientOrOrganization) ?? ""
    eventName = try c.decodeIfPresent(String.self, forKey: .eventName) ?? ""
    eventDate = try c.decodeIfPresent(Date.self, forKey: .eventDate)
    location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
    cameraOperator = try c.decodeIfPresent(String.self, forKey: .cameraOperator) ?? ""
    cameraModel = try c.decodeIfPresent(String.self, forKey: .cameraModel) ?? ""
    notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    defaultTags = try c.decodeIfPresent([String].self, forKey: .defaultTags) ?? []
  }

  private static func inferIngestStatus(
    from clips: [Clip],
    ingestIncomplete: Bool
  ) -> ProjectIngestStatus {
    guard !clips.isEmpty else {
      return ingestIncomplete ? .incomplete : .notStarted
    }

    if clips.allSatisfy({ $0.verificationStatus == .verified }) {
      return .complete
    }

    let copiedOrVerifiedClipCount = clips.filter {
      $0.copyStatus == .copied || $0.verificationStatus == .copied || $0.verificationStatus == .verified
    }.count

    if copiedOrVerifiedClipCount > 0 || ingestIncomplete {
      return .incomplete
    }

    return .notStarted
  }
}
