import SwiftUI

struct IngestProgressView: View {
  let progress: IngestProgress

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Copying file \(progress.currentIndex) of \(progress.totalCount)")
      Text(progress.currentFilename).font(.headline).lineLimit(1)
      ProgressView(value: progress.fraction)
      ProgressView(value: progress.fraction) { Text("Current file progress") }
      Text("Overall: \(Int(progress.fraction * 100))%")
      Text("\(FileSizeFormatterUtil.string(progress.copiedBytes)) of \(FileSizeFormatterUtil.string(progress.totalBytes)) • \(FileSizeFormatterUtil.string(Int64(progress.bytesPerSecond)))/s")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text("Estimated time remaining: \(eta)")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text("Keep the SD card and destination drive connected until ingest finishes.")
        .font(.caption.bold())
        .foregroundStyle(.orange)
    }
  }

  var eta: String {
    guard progress.bytesPerSecond > 0 else { return "calculating" }
    let remaining = Double(max(0, progress.totalBytes - progress.copiedBytes)) / progress.bytesPerSecond
    return DurationFormatterUtil.string(remaining)
  }
}
