import SwiftUI

struct ClipCardView: View {
  let clip: Clip
  let selected: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ZStack(alignment: .bottomLeading) {
        Rectangle().fill(.quaternary).aspectRatio(16 / 9, contentMode: .fit)
        if let path = clip.thumbnailPath, let image = NSImage(contentsOfFile: path) {
          Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipped()
        } else {
          Image(systemName: "video.fill")
            .font(.largeTitle)
            .foregroundStyle(.secondary)
        }
        StatusBadge(status: clip.cullStatus).padding(6)
      }
      Text(clip.currentFilename).font(.headline).lineLimit(1)
      HStack {
        Text(DurationFormatterUtil.string(clip.duration))
        Spacer()
        Text(clip.verificationStatus.rawValue.capitalized)
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(8)
    .background(selected ? Color.accentColor.opacity(0.20) : Color(nsColor: .controlBackgroundColor))
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(selected ? Color.accentColor : .clear, lineWidth: 3)
    )
    .clipShape(RoundedRectangle(cornerRadius: 12))
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
    case .keep: .green.opacity(0.85)
    case .maybe: .yellow.opacity(0.85)
    case .reject: .gray.opacity(0.65)
    case .unrated: .black.opacity(0.18)
    }
  }

  var foreground: Color { status == .maybe ? .black : .white }
}
