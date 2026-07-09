import Foundation
import Metal

enum ProcessorClass: String, CaseIterable, Identifiable {
  case basic
  case recommended
  case pro
  case unknown

  var id: String { rawValue }
}

struct SystemPerformanceProfile: Sendable {
  let isAppleSilicon: Bool
  let processorClass: ProcessorClass
  let physicalMemoryGB: Int
  let isLowMemory: Bool
  let supportsHeavyAnalysis: Bool
  let recommendedThumbnailConcurrency: Int
  let recommendedAnalysisConcurrency: Int

  static func current() -> SystemPerformanceProfile {
    #if arch(arm64)
    let appleSilicon = true
    #else
    let appleSilicon = false
    #endif

    let memoryBytes = ProcessInfo.processInfo.physicalMemory
    let memoryGB = max(1, Int((memoryBytes + 1_073_741_823) / 1_073_741_824))
    let hasMetal = MTLCreateSystemDefaultDevice() != nil
    let processorClass: ProcessorClass

    if !appleSilicon {
      processorClass = .unknown
    } else if memoryGB >= 32 && hasMetal {
      processorClass = .pro
    } else if memoryGB >= 16 && hasMetal {
      processorClass = .recommended
    } else {
      processorClass = .basic
    }

    let lowMemory = memoryGB < 16
    let thumbnailConcurrency: Int
    let analysisConcurrency: Int

    switch processorClass {
    case .pro:
      thumbnailConcurrency = 4
      analysisConcurrency = 2
    case .recommended:
      thumbnailConcurrency = 3
      analysisConcurrency = 2
    case .basic, .unknown:
      thumbnailConcurrency = 2
      analysisConcurrency = 1
    }

    return SystemPerformanceProfile(
      isAppleSilicon: appleSilicon,
      processorClass: processorClass,
      physicalMemoryGB: memoryGB,
      isLowMemory: lowMemory,
      supportsHeavyAnalysis: appleSilicon && hasMetal && !lowMemory,
      recommendedThumbnailConcurrency: thumbnailConcurrency,
      recommendedAnalysisConcurrency: analysisConcurrency
    )
  }
}
