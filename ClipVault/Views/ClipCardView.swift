import AppKit
import SwiftUI

struct ClipCardView: View {
  let clip: Clip
  let selected: Bool
  let canPreview: Bool
  let thumbnailURL: URL?
  let preview: () -> Void
  let rate: (Int) -> Void
  @State private var hovering = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ZStack(alignment: .bottomLeading) {
        thumbnail
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

        LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

        StatusBadge(status: clip.cullStatus)
          .padding(8)

        VStack {
          HStack {
            Spacer()
            VerificationBadge(status: clip.verificationStatus)
          }
          Spacer()
          if hovering {
            HStack {
              Button("Preview", systemImage: "play.fill", action: preview)
                .buttonStyle(.borderedProminent)
                .disabled(!canPreview)
              Spacer()
              quickButton("5★", 5)
              quickButton("3★", 3)
              quickButton("1★", 1)
            }
            .padding(8)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
          }
        }
      }
      .aspectRatio(16 / 9, contentMode: .fit)

      Text(clip.currentFilename)
        .font(.headline)
        .lineLimit(1)
        .truncationMode(.middle)

      HStack(spacing: 8) {
        StarRatingView(rating: clip.rating, onRate: rate)
        Spacer()
        if let quality = clip.analysisQualityScore {
          Text("Q \(Int(quality))")
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(qualityColor(quality).opacity(0.16), in: Capsule())
            .foregroundStyle(qualityColor(quality))
            .help("Analysis quality score from focus, stability, and exposure")
        }
      }

      HStack(spacing: 8) {
        Label(DurationFormatterUtil.string(clip.duration), systemImage: "timer")
        Spacer()
        Text(metadataSummary)
          .lineLimit(1)
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(10)
    .background(hovering ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
    .overlay(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 3 : 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .shadow(color: .black.opacity(selected ? 0.16 : 0.06), radius: selected ? 10 : 4, y: 3)
    .onHover { hovering = $0 }
  }

  @ViewBuilder private var thumbnail: some View {
    if let thumbnailURL, let image = NSImage(contentsOf: thumbnailURL) {
      Image(nsImage: image)
        .resizable()
        .scaledToFill()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    } else {
      ZStack {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(.quaternary)
        VStack(spacing: 8) {
          Image(systemName: placeholderIcon)
            .font(.system(size: 34, weight: .semibold))
          Text(thumbnailPlaceholderText)
            .font(.caption)
        }
        .foregroundStyle(.secondary)
      }
    }
  }

  private var thumbnailPlaceholderText: String {
    if clip.copyStatus == .pending || clip.copyStatus == .copying {
      return "Pending — not copied yet"
    }
    if clip.thumbnailStatus == .generating {
      return "Generating thumbnail…"
    }
    if clip.thumbnailStatus == .failed {
      return "Thumbnail unavailable"
    }
    return "Video thumbnail pending"
  }

  private var placeholderIcon: String {
    if clip.copyStatus == .pending || clip.copyStatus == .copying { return "clock" }
    if clip.thumbnailStatus == .failed { return "exclamationmark.triangle.fill" }
    if clip.thumbnailStatus == .generating { return "hourglass" }
    return "video"
  }

  private var metadataSummary: String {
    let resolution = clip.width.map { width in "\(width)p" } ?? "Video"
    let rate = clip.frameRate.map { String(format: "%.0fp", $0) } ?? ""
    return [resolution, rate].filter { !$0.isEmpty }.joined(separator: " • ")
  }

  private func quickButton(_ title: String, _ rating: Int) -> some View {
    Button(title) { rate(rating) }
      .buttonStyle(.bordered)
      .controlSize(.small)
  }

  private func qualityColor(_ quality: Double) -> Color {
    if quality >= 75 { return .green }
    if quality >= 45 { return .orange }
    return .red
  }
}

struct StarRatingView: View {
  let rating: Int
  var onRate: ((Int) -> Void)?

  var body: some View {
    HStack(spacing: 2) {
      ForEach(1...5, id: \.self) { star in
        Image(systemName: star <= rating ? "star.fill" : "star")
          .font(.caption)
          .foregroundStyle(star <= rating ? Color.yellow : Color.secondary.opacity(0.5))
          .onTapGesture {
            // Clicking the current rating clears it back to unrated.
            onRate?(star == rating ? 0 : star)
          }
      }
    }
  }
}

struct VerificationBadge: View {
  let status: VerificationStatus

  var body: some View {
    Label(status.rawValue.capitalized, systemImage: icon)
      .font(.caption2.bold())
      .padding(.horizontal, 7)
      .padding(.vertical, 4)
      .background(.thinMaterial, in: Capsule())
      .padding(8)
  }

  private var icon: String {
    switch status {
    case .verified: return "checkmark.seal.fill"
    case .failed: return "exclamationmark.triangle.fill"
    case .pending: return "clock"
    case .copied: return "doc.on.doc.fill"
    }
  }
}

struct StatusBadge: View {
  let status: CullStatus

  var body: some View {
    Text(status.label)
      .font(.caption.bold())
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .foregroundStyle(foreground)
      .background(background)
      .clipShape(Capsule())
  }

  var background: Color {
    switch status {
    case .keep: .green.opacity(0.88)
    case .maybe: .yellow.opacity(0.90)
    case .reject: .red.opacity(0.70)
    case .unrated: .black.opacity(0.24)
    }
  }

  var foreground: Color { status == .maybe ? .black : .white }
}
