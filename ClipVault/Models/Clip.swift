import CoreTransferable
import Foundation
import UniformTypeIdentifiers

enum ShotTimeSource: String, Codable, CaseIterable {
  case cameraMetadata
  case fileCreationDate
  case fileModifiedDate
  case filenamePattern
  case manual
  case unavailable

  var label: String {
    switch self {
    case .cameraMetadata: return "From camera metadata"
    case .fileCreationDate: return "From file creation date"
    case .fileModifiedDate: return "From file modified date"
    case .filenamePattern: return "From filename"
    case .manual: return "Manual override"
    case .unavailable: return "Unavailable"
    }
  }
}

enum AnalysisStatus: String, Codable, CaseIterable {
  case notAnalyzed
  case analyzing
  case complete
  case failed
  case canceled

  var label: String {
    switch self {
    case .notAnalyzed: return "Not Analyzed"
    case .analyzing: return "Analyzing"
    case .complete: return "Complete"
    case .failed: return "Failed Analysis"
    case .canceled: return "Canceled"
    }
  }
}

struct Clip: Identifiable, Codable, Equatable, Transferable {
  var id = UUID()
  var originalSourcePath: String
  var sourcePath: String = ""
  var sourceBookmarkData: Data?
  var originalFilename: String
  var sourceRelativePath: String = ""
  var expectedFileSize: Int64 = 0
  var currentPath: String
  var currentFilename: String
  var destinationRelativePath: String = ""
  var relativePath: String
  var fileSize: Int64
  var copyStatus: ClipCopyStatus = .copied
  var duration: Double?
  var width: Int?
  var height: Int?
  var frameRate: Double?
  var codec: String?
  var bitDepth: Int?
  var hasAudio: Bool?
  var audioChannelCount: Int?
  var orientation: String?
  var estimatedBitrate: Double?
  var createdAt: Date?
  var modifiedAt: Date?
  var capturedAt: Date?
  var shotStartTime: Date?
  var manualShotTime: Date?
  var shotTimeSource: ShotTimeSource = .unavailable
  var ingestDate: Date?
  var sonyCardFolderPath: String?
  var cardVolumeName: String?
  var checksum: String?
  var verificationStatus: VerificationStatus = .pending
  var cullStatus: CullStatus = .unrated
  var assignedFolder: String?
  var thumbnailPath: String?
  var thumbnailStatus: ThumbnailStatus = .pending
  var errorMessage: String?
  var previewUnavailable: Bool = false

  var title: String = ""
  var description: String = ""
  var productionTags: [String] = []
  var people: [String] = []
  var location: String = ""
  var scene: String = ""
  var shotType: String = ""
  var camera: String = ""
  var lens: String = ""
  var audioNotes: String = ""
  var transcriptNotes: String = ""
  var usageNotes: String = ""
  var colorLabel: String = ""
  var favorite: Bool = false
  var isBroll: Bool = false
  var isSermon: Bool = false
  var isInterview: Bool = false
  var isSocialClipCandidate: Bool = false
  var customNotes: String = ""
  var automaticTags: [String] = []
  var analysisStatus: AnalysisStatus = .notAnalyzed
  var focusScore: Double?
  var focusConfidence: Double?
  var sampledFrameCount: Int?
  var focusWarning: Bool = false
  var maxFaceCount: Int?
  var averageFaceCount: Double?
  var hasFaces: Bool = false
  var hasCloseFace: Bool = false
  var faceVisibilityScore: Double?
  var uniqueFaceAppearanceCount: Int?
  var stabilityScore: Double?
  var possiblyShaky: Bool = false
  var brightnessScore: Double?
  var contrastScore: Double?
  var darkFramePercentage: Double?
  var brightFramePercentage: Double?
  var exposureWarning: Bool = false
  var whiteBalanceKelvin: Int?
  var whiteBalanceTint: Double?
  var whiteBalanceConfidence: Double?
  var whiteBalanceSource: String = "unavailable"
  var largestFaceCoveragePercent: Double?
  var bestFaceFrameTime: Double?
  var possibleGroupShot: Bool = false
  var lowFaceVisibility: Bool = false
  var facePartiallyVisible: Bool = false
  var uniqueFaceConfidence: Double?
  var shakeScore: Double?
  var motionScore: Double?
  var highMotion: Bool = false

  enum CodingKeys: String, CodingKey {
    case id, originalSourcePath, sourcePath, sourceBookmarkData, originalFilename, sourceRelativePath
    case expectedFileSize, currentPath, currentFilename, destinationRelativePath, relativePath, fileSize
    case copyStatus, duration, width, height, frameRate, codec, bitDepth, hasAudio, audioChannelCount
    case orientation, estimatedBitrate, createdAt, modifiedAt, capturedAt, shotStartTime, manualShotTime
    case shotTimeSource, ingestDate, sonyCardFolderPath, cardVolumeName
    case checksum, verificationStatus, cullStatus, assignedFolder, thumbnailPath, thumbnailStatus, errorMessage
    case previewUnavailable, title, description, productionTags, people, location, scene, shotType, camera
    case lens, audioNotes, transcriptNotes, usageNotes, colorLabel, favorite, isBroll, isSermon
    case isInterview, isSocialClipCandidate, customNotes, automaticTags, analysisStatus, focusScore
    case focusConfidence, sampledFrameCount, focusWarning, maxFaceCount, averageFaceCount, hasFaces
    case hasCloseFace, faceVisibilityScore, uniqueFaceAppearanceCount, stabilityScore, possiblyShaky
    case brightnessScore, contrastScore, darkFramePercentage, brightFramePercentage, exposureWarning
    case whiteBalanceKelvin, whiteBalanceTint, whiteBalanceConfidence, whiteBalanceSource
    case largestFaceCoveragePercent, bestFaceFrameTime, possibleGroupShot, lowFaceVisibility
    case facePartiallyVisible, uniqueFaceConfidence, shakeScore, motionScore, highMotion
  }

  init(
    id: UUID = UUID(),
    originalSourcePath: String,
    originalFilename: String,
    currentPath: String,
    currentFilename: String,
    relativePath: String,
    fileSize: Int64,
    createdAt: Date? = nil,
    modifiedAt: Date? = nil,
    ingestDate: Date? = nil,
    sonyCardFolderPath: String? = nil,
    cardVolumeName: String? = nil
  ) {
    self.id = id
    self.originalSourcePath = originalSourcePath
    self.sourcePath = originalSourcePath
    self.originalFilename = originalFilename
    self.sourceRelativePath = relativePath
    self.expectedFileSize = fileSize
    self.currentPath = currentPath
    self.currentFilename = currentFilename
    self.destinationRelativePath = relativePath
    self.relativePath = relativePath
    self.fileSize = fileSize
    self.createdAt = createdAt
    self.modifiedAt = modifiedAt
    self.capturedAt = createdAt
    self.shotStartTime = createdAt ?? modifiedAt
    self.shotTimeSource = createdAt == nil ? (modifiedAt == nil ? .unavailable : .fileModifiedDate) : .fileCreationDate
    self.ingestDate = ingestDate
    self.sonyCardFolderPath = sonyCardFolderPath
    self.cardVolumeName = cardVolumeName
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    originalSourcePath = try c.decodeIfPresent(String.self, forKey: .originalSourcePath) ?? ""
    sourcePath = try c.decodeIfPresent(String.self, forKey: .sourcePath) ?? originalSourcePath
    sourceBookmarkData = try c.decodeIfPresent(Data.self, forKey: .sourceBookmarkData)
    originalFilename = try c.decodeIfPresent(String.self, forKey: .originalFilename) ?? URL(fileURLWithPath: sourcePath).lastPathComponent
    sourceRelativePath = try c.decodeIfPresent(String.self, forKey: .sourceRelativePath) ?? ""
    expectedFileSize = try c.decodeIfPresent(Int64.self, forKey: .expectedFileSize) ?? 0
    currentPath = try c.decodeIfPresent(String.self, forKey: .currentPath) ?? ""
    currentFilename = try c.decodeIfPresent(String.self, forKey: .currentFilename) ?? (currentPath.isEmpty ? originalFilename : URL(fileURLWithPath: currentPath).lastPathComponent)
    destinationRelativePath = try c.decodeIfPresent(String.self, forKey: .destinationRelativePath) ?? ""
    relativePath = try c.decodeIfPresent(String.self, forKey: .relativePath) ?? destinationRelativePath
    fileSize = try c.decodeIfPresent(Int64.self, forKey: .fileSize) ?? expectedFileSize
    copyStatus = try c.decodeIfPresent(ClipCopyStatus.self, forKey: .copyStatus) ?? (currentPath.isEmpty ? .pending : .copied)
    verificationStatus = try c.decodeIfPresent(VerificationStatus.self, forKey: .verificationStatus) ?? (currentPath.isEmpty ? .pending : .copied)
    cullStatus = try c.decodeIfPresent(CullStatus.self, forKey: .cullStatus) ?? .unrated
    thumbnailStatus = try c.decodeIfPresent(ThumbnailStatus.self, forKey: .thumbnailStatus) ?? .pending
    analysisStatus = try c.decodeIfPresent(AnalysisStatus.self, forKey: .analysisStatus) ?? .notAnalyzed
    // Decode remaining optional/simple fields with defaults.
    duration = try c.decodeIfPresent(Double.self, forKey: .duration)
    width = try c.decodeIfPresent(Int.self, forKey: .width)
    height = try c.decodeIfPresent(Int.self, forKey: .height)
    frameRate = try c.decodeIfPresent(Double.self, forKey: .frameRate)
    codec = try c.decodeIfPresent(String.self, forKey: .codec)
    bitDepth = try c.decodeIfPresent(Int.self, forKey: .bitDepth)
    hasAudio = try c.decodeIfPresent(Bool.self, forKey: .hasAudio)
    audioChannelCount = try c.decodeIfPresent(Int.self, forKey: .audioChannelCount)
    orientation = try c.decodeIfPresent(String.self, forKey: .orientation)
    estimatedBitrate = try c.decodeIfPresent(Double.self, forKey: .estimatedBitrate)
    createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt)
    capturedAt = try c.decodeIfPresent(Date.self, forKey: .capturedAt)
    shotStartTime = try c.decodeIfPresent(Date.self, forKey: .shotStartTime)
    manualShotTime = try c.decodeIfPresent(Date.self, forKey: .manualShotTime)
    shotTimeSource = try c.decodeIfPresent(ShotTimeSource.self, forKey: .shotTimeSource) ?? .unavailable
    ingestDate = try c.decodeIfPresent(Date.self, forKey: .ingestDate)
    sonyCardFolderPath = try c.decodeIfPresent(String.self, forKey: .sonyCardFolderPath)
    cardVolumeName = try c.decodeIfPresent(String.self, forKey: .cardVolumeName)
    checksum = try c.decodeIfPresent(String.self, forKey: .checksum)
    assignedFolder = try c.decodeIfPresent(String.self, forKey: .assignedFolder)
    thumbnailPath = try c.decodeIfPresent(String.self, forKey: .thumbnailPath)
    errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
    previewUnavailable = try c.decodeIfPresent(Bool.self, forKey: .previewUnavailable) ?? false
    title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
    description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
    productionTags = try c.decodeIfPresent([String].self, forKey: .productionTags) ?? []
    people = try c.decodeIfPresent([String].self, forKey: .people) ?? []
    location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
    scene = try c.decodeIfPresent(String.self, forKey: .scene) ?? ""
    shotType = try c.decodeIfPresent(String.self, forKey: .shotType) ?? ""
    camera = try c.decodeIfPresent(String.self, forKey: .camera) ?? ""
    lens = try c.decodeIfPresent(String.self, forKey: .lens) ?? ""
    audioNotes = try c.decodeIfPresent(String.self, forKey: .audioNotes) ?? ""
    transcriptNotes = try c.decodeIfPresent(String.self, forKey: .transcriptNotes) ?? ""
    usageNotes = try c.decodeIfPresent(String.self, forKey: .usageNotes) ?? ""
    colorLabel = try c.decodeIfPresent(String.self, forKey: .colorLabel) ?? ""
    favorite = try c.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
    isBroll = try c.decodeIfPresent(Bool.self, forKey: .isBroll) ?? false
    isSermon = try c.decodeIfPresent(Bool.self, forKey: .isSermon) ?? false
    isInterview = try c.decodeIfPresent(Bool.self, forKey: .isInterview) ?? false
    isSocialClipCandidate = try c.decodeIfPresent(Bool.self, forKey: .isSocialClipCandidate) ?? false
    customNotes = try c.decodeIfPresent(String.self, forKey: .customNotes) ?? ""
    automaticTags = try c.decodeIfPresent([String].self, forKey: .automaticTags) ?? []
    focusScore = try c.decodeIfPresent(Double.self, forKey: .focusScore)
    focusConfidence = try c.decodeIfPresent(Double.self, forKey: .focusConfidence)
    sampledFrameCount = try c.decodeIfPresent(Int.self, forKey: .sampledFrameCount)
    focusWarning = try c.decodeIfPresent(Bool.self, forKey: .focusWarning) ?? false
    maxFaceCount = try c.decodeIfPresent(Int.self, forKey: .maxFaceCount)
    averageFaceCount = try c.decodeIfPresent(Double.self, forKey: .averageFaceCount)
    hasFaces = try c.decodeIfPresent(Bool.self, forKey: .hasFaces) ?? false
    hasCloseFace = try c.decodeIfPresent(Bool.self, forKey: .hasCloseFace) ?? false
    faceVisibilityScore = try c.decodeIfPresent(Double.self, forKey: .faceVisibilityScore)
    uniqueFaceAppearanceCount = try c.decodeIfPresent(Int.self, forKey: .uniqueFaceAppearanceCount)
    stabilityScore = try c.decodeIfPresent(Double.self, forKey: .stabilityScore)
    possiblyShaky = try c.decodeIfPresent(Bool.self, forKey: .possiblyShaky) ?? false
    brightnessScore = try c.decodeIfPresent(Double.self, forKey: .brightnessScore)
    contrastScore = try c.decodeIfPresent(Double.self, forKey: .contrastScore)
    darkFramePercentage = try c.decodeIfPresent(Double.self, forKey: .darkFramePercentage)
    brightFramePercentage = try c.decodeIfPresent(Double.self, forKey: .brightFramePercentage)
    exposureWarning = try c.decodeIfPresent(Bool.self, forKey: .exposureWarning) ?? false
    whiteBalanceKelvin = try c.decodeIfPresent(Int.self, forKey: .whiteBalanceKelvin)
    whiteBalanceTint = try c.decodeIfPresent(Double.self, forKey: .whiteBalanceTint)
    whiteBalanceConfidence = try c.decodeIfPresent(Double.self, forKey: .whiteBalanceConfidence)
    whiteBalanceSource = try c.decodeIfPresent(String.self, forKey: .whiteBalanceSource) ?? "unavailable"
    largestFaceCoveragePercent = try c.decodeIfPresent(Double.self, forKey: .largestFaceCoveragePercent)
    bestFaceFrameTime = try c.decodeIfPresent(Double.self, forKey: .bestFaceFrameTime)
    possibleGroupShot = try c.decodeIfPresent(Bool.self, forKey: .possibleGroupShot) ?? false
    lowFaceVisibility = try c.decodeIfPresent(Bool.self, forKey: .lowFaceVisibility) ?? false
    facePartiallyVisible = try c.decodeIfPresent(Bool.self, forKey: .facePartiallyVisible) ?? false
    uniqueFaceConfidence = try c.decodeIfPresent(Double.self, forKey: .uniqueFaceConfidence)
    shakeScore = try c.decodeIfPresent(Double.self, forKey: .shakeScore)
    motionScore = try c.decodeIfPresent(Double.self, forKey: .motionScore)
    highMotion = try c.decodeIfPresent(Bool.self, forKey: .highMotion) ?? false
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(originalSourcePath, forKey: .originalSourcePath)
    try c.encode(sourcePath, forKey: .sourcePath)
    try c.encodeIfPresent(sourceBookmarkData, forKey: .sourceBookmarkData)
    try c.encode(originalFilename, forKey: .originalFilename)
    try c.encode(sourceRelativePath, forKey: .sourceRelativePath)
    try c.encode(expectedFileSize, forKey: .expectedFileSize)
    try c.encode(currentPath, forKey: .currentPath)
    try c.encode(currentFilename, forKey: .currentFilename)
    try c.encode(destinationRelativePath, forKey: .destinationRelativePath)
    try c.encode(relativePath, forKey: .relativePath)
    try c.encode(fileSize, forKey: .fileSize)
    try c.encode(copyStatus, forKey: .copyStatus)
    try c.encodeIfPresent(duration, forKey: .duration)
    try c.encodeIfPresent(width, forKey: .width)
    try c.encodeIfPresent(height, forKey: .height)
    try c.encodeIfPresent(frameRate, forKey: .frameRate)
    try c.encodeIfPresent(codec, forKey: .codec)
    try c.encodeIfPresent(bitDepth, forKey: .bitDepth)
    try c.encodeIfPresent(hasAudio, forKey: .hasAudio)
    try c.encodeIfPresent(audioChannelCount, forKey: .audioChannelCount)
    try c.encodeIfPresent(orientation, forKey: .orientation)
    try c.encodeIfPresent(estimatedBitrate, forKey: .estimatedBitrate)
    try c.encodeIfPresent(createdAt, forKey: .createdAt)
    try c.encodeIfPresent(modifiedAt, forKey: .modifiedAt)
    try c.encodeIfPresent(capturedAt, forKey: .capturedAt)
    try c.encodeIfPresent(shotStartTime, forKey: .shotStartTime)
    try c.encodeIfPresent(manualShotTime, forKey: .manualShotTime)
    try c.encode(shotTimeSource, forKey: .shotTimeSource)
    try c.encodeIfPresent(ingestDate, forKey: .ingestDate)
    try c.encodeIfPresent(sonyCardFolderPath, forKey: .sonyCardFolderPath)
    try c.encodeIfPresent(cardVolumeName, forKey: .cardVolumeName)
    try c.encodeIfPresent(checksum, forKey: .checksum)
    try c.encode(verificationStatus, forKey: .verificationStatus)
    try c.encode(cullStatus, forKey: .cullStatus)
    try c.encodeIfPresent(assignedFolder, forKey: .assignedFolder)
    try c.encodeIfPresent(thumbnailPath, forKey: .thumbnailPath)
    try c.encode(thumbnailStatus, forKey: .thumbnailStatus)
    try c.encodeIfPresent(errorMessage, forKey: .errorMessage)
    try c.encode(previewUnavailable, forKey: .previewUnavailable)
    try c.encode(title, forKey: .title)
    try c.encode(description, forKey: .description)
    try c.encode(productionTags, forKey: .productionTags)
    try c.encode(people, forKey: .people)
    try c.encode(location, forKey: .location)
    try c.encode(scene, forKey: .scene)
    try c.encode(shotType, forKey: .shotType)
    try c.encode(camera, forKey: .camera)
    try c.encode(lens, forKey: .lens)
    try c.encode(audioNotes, forKey: .audioNotes)
    try c.encode(transcriptNotes, forKey: .transcriptNotes)
    try c.encode(usageNotes, forKey: .usageNotes)
    try c.encode(colorLabel, forKey: .colorLabel)
    try c.encode(favorite, forKey: .favorite)
    try c.encode(isBroll, forKey: .isBroll)
    try c.encode(isSermon, forKey: .isSermon)
    try c.encode(isInterview, forKey: .isInterview)
    try c.encode(isSocialClipCandidate, forKey: .isSocialClipCandidate)
    try c.encode(customNotes, forKey: .customNotes)
    try c.encode(automaticTags, forKey: .automaticTags)
    try c.encode(analysisStatus, forKey: .analysisStatus)
    try c.encodeIfPresent(focusScore, forKey: .focusScore)
    try c.encodeIfPresent(focusConfidence, forKey: .focusConfidence)
    try c.encodeIfPresent(sampledFrameCount, forKey: .sampledFrameCount)
    try c.encode(focusWarning, forKey: .focusWarning)
    try c.encodeIfPresent(maxFaceCount, forKey: .maxFaceCount)
    try c.encodeIfPresent(averageFaceCount, forKey: .averageFaceCount)
    try c.encode(hasFaces, forKey: .hasFaces)
    try c.encode(hasCloseFace, forKey: .hasCloseFace)
    try c.encodeIfPresent(faceVisibilityScore, forKey: .faceVisibilityScore)
    try c.encodeIfPresent(uniqueFaceAppearanceCount, forKey: .uniqueFaceAppearanceCount)
    try c.encodeIfPresent(stabilityScore, forKey: .stabilityScore)
    try c.encode(possiblyShaky, forKey: .possiblyShaky)
    try c.encodeIfPresent(brightnessScore, forKey: .brightnessScore)
    try c.encodeIfPresent(contrastScore, forKey: .contrastScore)
    try c.encodeIfPresent(darkFramePercentage, forKey: .darkFramePercentage)
    try c.encodeIfPresent(brightFramePercentage, forKey: .brightFramePercentage)
    try c.encode(exposureWarning, forKey: .exposureWarning)
    try c.encodeIfPresent(whiteBalanceKelvin, forKey: .whiteBalanceKelvin)
    try c.encodeIfPresent(whiteBalanceTint, forKey: .whiteBalanceTint)
    try c.encodeIfPresent(whiteBalanceConfidence, forKey: .whiteBalanceConfidence)
    try c.encode(whiteBalanceSource, forKey: .whiteBalanceSource)
    try c.encodeIfPresent(largestFaceCoveragePercent, forKey: .largestFaceCoveragePercent)
    try c.encodeIfPresent(bestFaceFrameTime, forKey: .bestFaceFrameTime)
    try c.encode(possibleGroupShot, forKey: .possibleGroupShot)
    try c.encode(lowFaceVisibility, forKey: .lowFaceVisibility)
    try c.encode(facePartiallyVisible, forKey: .facePartiallyVisible)
    try c.encodeIfPresent(uniqueFaceConfidence, forKey: .uniqueFaceConfidence)
    try c.encodeIfPresent(shakeScore, forKey: .shakeScore)
    try c.encodeIfPresent(motionScore, forKey: .motionScore)
    try c.encode(highMotion, forKey: .highMotion)
  }

  var effectiveShotTime: Date? { manualShotTime ?? shotStartTime ?? capturedAt ?? createdAt ?? modifiedAt }

  static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: .data)
  }
}
