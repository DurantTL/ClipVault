import AppKit
import SwiftUI

struct SessionCard: View {
  let session: IngestSession
  @Binding var selected: Bool
  let preflightResults: [UUID: PreflightClipResult]
  let onToggleSession: () -> Void
  let onSetClip: (ScannedVideo, Bool) -> Void
  let onQueueClipThumbnail: (ScannedVideo) -> Void
  let onQueueSessionThumbnails: (IngestSession) -> Void
  @State private var expanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 14) {
        Toggle("", isOn: $selected)
          .labelsHidden()
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text(session.title)
              .font(.headline)
            badge(session.cameraType, color: .secondary)
            if selected && !session.isPartiallySelected {
              badge("Selected", color: .accentColor)
            }
            if session.isPartiallySelected {
              badge("Partial selection", color: .orange)
            }
          }

          if !sessionPreflightResults.isEmpty {
            HStack(spacing: 6) {
              if newCount > 0 { badge("New \(newCount)", color: .green) }
              if importedCount > 0 { badge("Imported \(importedCount)", color: .blue) }
              if reviewCount > 0 { badge("Review \(reviewCount)", color: .orange) }
            }
          }

          Text("\(session.selectedClipCount) of \(session.clips.count) videos selected • \(FileSizeFormatterUtil.string(session.selectedSize)) • \(timeRange)")
            .font(.caption)
            .foregroundStyle(.secondary)
          thumbnailStrip
        }
        Spacer()
        Button { expanded.toggle() } label: {
          Label(
            expanded ? "Collapse" : "Expand",
            systemImage: expanded ? "chevron.up" : "chevron.down"
          )
        }
        .buttonStyle(.borderless)
      }
      .contentShape(Rectangle())
      .onTapGesture { onToggleSession() }

      if expanded {
        Divider()
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 220), spacing: 8)],
          alignment: .leading,
          spacing: 8
        ) {
          ForEach(session.clips) { clip in
            ClipSelectionRow(
              clip: clip,
              isSelected: Binding(
                get: { clip.selected },
                set: { onSetClip(clip, $0) }
              ),
              preflightResult: preflightResults[clip.id],
              onQueueThumbnail: { onQueueClipThumbnail(clip) }
            )
          }
        }
      }
    }
    .padding(14)
    .background(
      selected
        ? Color.accentColor.opacity(0.12)
        : Color(nsColor: .controlBackgroundColor),
      in: RoundedRectangle(cornerRadius: 16)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 16)
        .stroke(
          selected ? Color.accentColor : Color.secondary.opacity(0.16),
          lineWidth: selected ? 2 : 1
        )
    )
    .onAppear { onQueueSessionThumbnails(session) }
    .onChange(of: expanded) { isExpanded in
      if isExpanded { onQueueSessionThumbnails(session) }
    }
  }

  private var sessionPreflightResults: [PreflightClipResult] {
    session.clips.compactMap { preflightResults[$0.id] }
  }

  private var newCount: Int {
    sessionPreflightResults.filter { $0.status == .newMedia }.count
  }

  private var importedCount: Int {
    sessionPreflightResults.filter {
      $0.status == .alreadyInDestination
        || $0.status == .alreadyInAnotherProject
        || $0.status == .alreadyOnBackup
    }.count
  }

  private var reviewCount: Int {
    sessionPreflightResults.filter { $0.status.needsReview }.count
  }

  private var thumbnailStrip: some View {
    HStack(spacing: 6) {
      ForEach(Array(session.clips.prefix(7).enumerated()), id: \.element.id) { _, clip in
        IngestPreviewThumbnailView(clip: clip, width: 54, height: 38)
          .overlay(alignment: .topTrailing) {
            if let result = preflightResults[clip.id], result.status != .newMedia {
              Image(systemName: result.status.systemImage)
                .font(.caption2.bold())
                .foregroundStyle(result.status.color)
                .background(.thinMaterial, in: Circle())
                .padding(3)
            } else if clip.selected {
              Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .background(.thinMaterial, in: Circle())
                .padding(3)
            }
          }
          .onAppear { onQueueClipThumbnail(clip) }
      }
      if session.clips.count > 7 {
        Text("+\(session.clips.count - 7)")
          .font(.caption.bold())
          .frame(width: 54, height: 38)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
      }
    }
  }

  private func badge(_ text: String, color: Color) -> some View {
    Text(text)
      .font(.caption.bold())
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(color.opacity(0.14), in: Capsule())
      .foregroundStyle(color)
  }

  private var timeRange: String {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    return "\(formatter.string(from: session.startTime))–\(formatter.string(from: session.endTime))"
  }
}

struct ClipSelectionRow: View {
  let clip: ScannedVideo
  @Binding var isSelected: Bool
  let preflightResult: PreflightClipResult?
  let onQueueThumbnail: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      IngestPreviewThumbnailView(clip: clip, width: 54, height: 38)
        .onAppear(perform: onQueueThumbnail)
      Toggle(isOn: $isSelected) {
        VStack(alignment: .leading, spacing: 4) {
          Text(clip.filename)
            .font(.caption.bold())
            .lineLimit(1)
          Text(FileSizeFormatterUtil.string(clip.fileSize))
            .font(.caption2)
            .foregroundStyle(.secondary)
          if let preflightResult {
            PreflightStatusBadge(result: preflightResult, compact: true)
          }
        }
      }
      .toggleStyle(.checkbox)
    }
    .padding(8)
    .background(rowBackground, in: RoundedRectangle(cornerRadius: 10))
  }

  private var rowBackground: Color {
    if let preflightResult, preflightResult.status.needsReview {
      return preflightResult.status.color.opacity(isSelected ? 0.14 : 0.08)
    }
    return isSelected ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.06)
  }
}

struct IngestPreviewThumbnailView: View {
  let clip: ScannedVideo
  let width: CGFloat
  let height: CGFloat

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8)
        .fill(.quaternary)
      if let image = previewImage {
        Image(nsImage: image)
          .resizable()
          .scaledToFill()
          .frame(width: width, height: height)
          .clipped()
      } else if clip.previewThumbnailStatus == .generating {
        Text("Generating…")
          .font(.system(size: 8, weight: .medium))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(3)
      } else {
        Image(systemName: "film")
          .foregroundStyle(Color.secondary)
      }
    }
    .frame(width: width, height: height)
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  private var previewImage: NSImage? {
    guard let path = clip.previewThumbnailPath,
      FileManager.default.fileExists(atPath: path) else {
      return nil
    }
    return NSImage(contentsOfFile: path)
  }
}

struct SourceVolumeCard: View {
  let option: SourceVolumeOption
  let isSelected: Bool
  let onSelect: () -> Void

  var body: some View {
    Button(action: onSelect) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: option.iconName)
          .font(.title3)
          .frame(width: 24)
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text(option.name)
              .font(.subheadline.weight(.semibold))
              .lineLimit(1)
            if !option.isAvailable {
              Text("Disconnected")
                .font(.caption2.bold())
                .foregroundStyle(.red)
            }
          }
          Text(option.capacitySummary)
            .font(.caption)
            .foregroundStyle(.secondary)
          HStack(spacing: 5) {
            Text(option.volumeKind.rawValue)
              .font(.caption2.bold())
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(Color.secondary.opacity(0.12), in: Capsule())
            if option.structureBadge != .noVideosFound {
              Text(option.structureBadge.rawValue)
                .font(.caption2.bold())
                .foregroundStyle(
                  option.structureBadge == .sony
                    || option.structureBadge == .canonDCF
                    ? .green
                    : .secondary
                )
            }
          }
        }
        Spacer(minLength: 0)
      }
      .padding(9)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        isSelected
          ? Color.accentColor.opacity(0.18)
          : Color(nsColor: .controlBackgroundColor),
        in: RoundedRectangle(cornerRadius: 10)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .stroke(
            isSelected
              ? Color.accentColor.opacity(0.55)
              : Color.secondary.opacity(0.12)
          )
      )
    }
    .buttonStyle(.plain)
    .disabled(!option.isAvailable)
  }
}
