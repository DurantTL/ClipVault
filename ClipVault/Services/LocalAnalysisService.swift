import AVFoundation
import CoreImage
import Foundation
import Vision

enum LocalAnalysisMode: String, CaseIterable, Identifiable {
  case off = "Off"
  case fast = "Fast"
  case balanced = "Balanced"
  case detailed = "Detailed"

  var id: String { rawValue }

  func sampleTimes(duration: Double?) -> [Double] {
    let length = max(duration ?? 0, 1)
    switch self {
    case .off:
      return []
    case .fast:
      return evenlySpaced(count: 3, duration: length)
    case .balanced:
      return length > 50 ? stride(from: 1.0, through: length - 1, by: 10).map { $0 } : evenlySpaced(count: 5, duration: length)
    case .detailed:
      let step = length > 60 ? 5.0 : 2.0
      return Array(stride(from: 1.0, through: max(1, length - 1), by: step)).prefix(40).map { $0 }
    }
  }

  private func evenlySpaced(count: Int, duration: Double) -> [Double] {
    guard count > 0 else { return [] }
    return (0..<count).map { index in
      duration * (Double(index) + 0.5) / Double(count)
    }
  }
}

struct FrameSample {
  let time: Double
  let image: CGImage
}

struct FrameSamplerService {
  func samples(for url: URL, mode: LocalAnalysisMode, duration: Double?) async throws -> [FrameSample] {
    let asset = AVURLAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 480, height: 270)
    generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
    generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
    var frames: [FrameSample] = []
    for seconds in mode.sampleTimes(duration: duration) {
      try Task.checkCancellation()
      let result = try generator.copyCGImage(at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil)
      frames.append(FrameSample(time: seconds, image: result))
    }
    return frames
  }
}

struct FrameMetrics {
  var luminanceAverage: Double
  var darkPercent: Double
  var brightPercent: Double
  var contrast: Double
  var sharpness: Double
  var redAverage: Double
  var greenAverage: Double
  var blueAverage: Double
}

struct PixelAnalyzer {
  func metrics(for image: CGImage) -> FrameMetrics? {
    let width = min(image.width, 320)
    let height = max(1, Int(Double(image.height) * Double(width) / Double(image.width)))
    var data = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
      return nil
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    var lumas: [Double] = []
    lumas.reserveCapacity(width * height)
    var red = 0.0
    var green = 0.0
    var blue = 0.0
    var dark = 0
    var bright = 0
    for index in stride(from: 0, to: data.count, by: 4) {
      let r = Double(data[index]) / 255
      let g = Double(data[index + 1]) / 255
      let b = Double(data[index + 2]) / 255
      let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
      red += r; green += g; blue += b; lumas.append(y)
      if y < 0.12 { dark += 1 }
      if y > 0.88 { bright += 1 }
    }
    let count = Double(lumas.count)
    let avg = lumas.reduce(0, +) / count
    let variance = lumas.reduce(0) { $0 + pow($1 - avg, 2) } / count
    var edge = 0.0
    if width > 2 && height > 2 {
      for y in 1..<(height - 1) {
        for x in 1..<(width - 1) {
          let i = y * width + x
          let lap = 4 * lumas[i] - lumas[i - 1] - lumas[i + 1] - lumas[i - width] - lumas[i + width]
          edge += lap * lap
        }
      }
    }
    return FrameMetrics(luminanceAverage: avg, darkPercent: Double(dark) / count, brightPercent: Double(bright) / count, contrast: sqrt(variance), sharpness: edge / count, redAverage: red / count, greenAverage: green / count, blueAverage: blue / count)
  }
}

struct FocusAnalysisService {
  func apply(to clip: inout Clip, metrics: [FrameMetrics]) {
    let sharpness = metrics.map(\.sharpness).reduce(0, +) / Double(max(metrics.count, 1))
    let score = min(100, max(0, sharpness * 1800))
    clip.focusScore = score
    clip.focusConfidence = min(100, Double(metrics.count) * 22)
    clip.focusWarning = score < 38
  }
}

struct ExposureAnalysisService {
  func apply(to clip: inout Clip, metrics: [FrameMetrics]) {
    let avg = average(metrics.map(\.luminanceAverage))
    let dark = average(metrics.map(\.darkPercent)) * 100
    let bright = average(metrics.map(\.brightPercent)) * 100
    let contrast = average(metrics.map(\.contrast)) * 240
    clip.brightnessScore = min(100, max(0, avg * 100))
    clip.contrastScore = min(100, max(0, contrast))
    clip.darkFramePercentage = dark
    clip.brightFramePercentage = bright
    clip.exposureWarning = dark > 45 || bright > 35 || contrast < 18
  }

  private func average(_ values: [Double]) -> Double {
    values.reduce(0, +) / Double(max(values.count, 1))
  }
}

struct WhiteBalanceAnalysisService {
  func apply(to clip: inout Clip, metrics: [FrameMetrics]) {
    let r = average(metrics.map(\.redAverage))
    let g = average(metrics.map(\.greenAverage))
    let b = average(metrics.map(\.blueAverage))
    guard r > 0, g > 0, b > 0 else { return }
    let warmth = (r - b) / max(0.01, g)
    let kelvin = Int(min(9000, max(2500, 5200 - warmth * 2600)))
    clip.whiteBalanceKelvin = kelvin
    clip.whiteBalanceTint = (g - ((r + b) / 2)) * 100
    clip.whiteBalanceConfidence = min(100, Double(metrics.count) * 18)
    clip.whiteBalanceSource = "estimatedFromFrames"
  }

  private func average(_ values: [Double]) -> Double {
    values.reduce(0, +) / Double(max(values.count, 1))
  }
}

struct StabilityAnalysisService {
  func apply(to clip: inout Clip, metrics: [FrameMetrics]) {
    let changes = zip(metrics.dropFirst(), metrics).map { abs($0.luminanceAverage - $1.luminanceAverage) + abs($0.contrast - $1.contrast) }
    let motion = min(100, (changes.reduce(0, +) / Double(max(changes.count, 1))) * 400)
    clip.motionScore = motion
    clip.shakeScore = motion
    clip.stabilityScore = max(0, 100 - motion)
    clip.possiblyShaky = motion > 55
    clip.highMotion = motion > 70
  }
}

struct FaceAnalysisService {
  func apply(to clip: inout Clip, samples: [FrameSample]) async {
    var counts: [Int] = []
    var largest = 0.0
    var bestTime: Double?
    var partial = false
    for sample in samples {
      let request = VNDetectFaceRectanglesRequest()
      let handler = VNImageRequestHandler(cgImage: sample.image)
      try? handler.perform([request])
      let faces = request.results ?? []
      counts.append(faces.count)
      for face in faces {
        let area = face.boundingBox.width * face.boundingBox.height * 100
        if area > largest { largest = area; bestTime = sample.time }
        if face.boundingBox.minX < 0.03 || face.boundingBox.maxX > 0.97 || face.boundingBox.minY < 0.03 || face.boundingBox.maxY > 0.97 { partial = true }
      }
    }
    let maxCount = counts.max() ?? 0
    let averageCount = Double(counts.reduce(0, +)) / Double(max(counts.count, 1))
    clip.hasFaces = maxCount > 0
    clip.maxFaceCount = maxCount
    clip.averageFaceCount = averageCount
    clip.largestFaceCoveragePercent = largest
    clip.bestFaceFrameTime = bestTime
    clip.hasCloseFace = largest > 10
    clip.possibleGroupShot = maxCount >= 3
    clip.lowFaceVisibility = clip.hasFaces && largest < 2.5
    clip.facePartiallyVisible = partial
    clip.faceVisibilityScore = clip.hasFaces ? min(100, max(15, largest * 7 + averageCount * 12)) : nil
    clip.uniqueFaceAppearanceCount = clip.hasFaces ? min(maxCount, 3) : 0
    clip.uniqueFaceConfidence = clip.hasFaces ? min(70, Double(samples.count) * 14) : 0
  }
}

struct LocalAnalysisService {
  private let sampler = FrameSamplerService()
  private let pixels = PixelAnalyzer()

  func tags(for clip: Clip) -> [String] {
    var tags = Set(clip.automaticTags)
    if let width = clip.width, width >= 3840 { tags.insert("4K") }
    if let frameRate = clip.frameRate, frameRate >= 59.0 { tags.insert("60p") }
    if clip.hasAudio == true { tags.insert("Has Audio") }
    if clip.hasAudio == false { tags.insert("No Audio") }
    if let duration = clip.duration, duration < 30 { tags.insert("Short Clip") }
    if let duration = clip.duration, duration >= 300 { tags.insert("Long Clip") }
    if clip.fileSize >= 5_000_000_000 { tags.insert("Large File") }
    if clip.originalSourcePath.localizedCaseInsensitiveContains("PRIVATE/M4ROOT") || clip.sonyCardFolderPath != nil { tags.insert("Sony") }
    if clip.originalSourcePath.localizedCaseInsensitiveContains("/DCIM/") { tags.insert("Canon/DCF") }
    if clip.analysisStatus == .failed { tags.insert("Failed Analysis") }
    if clip.focusWarning { tags.insert("Possibly Out of Focus") }
    if let score = clip.focusScore, score >= 70 { tags.insert("Sharp Clips") }
    if let score = clip.focusScore, score < 25 { tags.insert("Low Detail") }
    if clip.hasFaces { tags.insert("Faces") }
    if clip.hasCloseFace { tags.insert("Close Faces") }
    if clip.possibleGroupShot { tags.insert("Group Shots") }
    if clip.lowFaceVisibility { tags.insert("Low Face Visibility") }
    if clip.facePartiallyVisible { tags.insert("Face Partially Visible") }
    if clip.possiblyShaky { tags.insert("Possibly Shaky") }
    if clip.stabilityScore ?? 0 >= 75 { tags.insert("Stable Clips") }
    if clip.highMotion { tags.insert("High Motion") }
    if clip.brightnessScore ?? 50 < 25 { tags.insert("Dark Clips") }
    if clip.brightnessScore ?? 50 > 82 { tags.insert("Bright Clips") }
    if clip.contrastScore ?? 50 < 18 { tags.insert("Low Contrast") }
    if clip.exposureWarning == false, clip.brightnessScore != nil { tags.insert("Balanced Exposure") }
    if let kelvin = clip.whiteBalanceKelvin {
      if kelvin < 4200 { tags.insert("Warm Color") }
      if kelvin > 6500 { tags.insert("Cool Color") }
      tags.insert("Approx. WB")
    }
    if (clip.whiteBalanceConfidence ?? 100) < 45 && clip.whiteBalanceKelvin != nil { tags.insert("White Balance Estimate Low Confidence") }
    return Array(tags).sorted()
  }

  func analyzed(_ input: Clip, mode: LocalAnalysisMode) async -> Clip {
    var clip = input
    guard mode != .off else { return clip }
    guard FileManager.default.fileExists(atPath: clip.currentPath) else { return clip }
    clip.analysisStatus = .analyzing
    do {
      let samples = try await sampler.samples(for: URL(fileURLWithPath: clip.currentPath), mode: mode, duration: clip.duration)
      let metrics = samples.compactMap { pixels.metrics(for: $0.image) }
      clip.sampledFrameCount = samples.count
      FocusAnalysisService().apply(to: &clip, metrics: metrics)
      ExposureAnalysisService().apply(to: &clip, metrics: metrics)
      WhiteBalanceAnalysisService().apply(to: &clip, metrics: metrics)
      StabilityAnalysisService().apply(to: &clip, metrics: metrics)
      await FaceAnalysisService().apply(to: &clip, samples: samples)
      clip.analysisStatus = .complete
    } catch is CancellationError {
      clip.analysisStatus = .canceled
    } catch {
      clip.analysisStatus = .failed
      clip.errorMessage = "Local analysis failed: \(error.localizedDescription)"
    }
    clip.automaticTags = tags(for: clip)
    return clip
  }
}
