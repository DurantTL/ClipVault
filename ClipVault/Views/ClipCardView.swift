import SwiftUI

struct ClipCardView: View {
  let clip: Clip
  let selected: Bool
  var body: some View {
    VStack(alignment: .leading) {
      ZStack {
        Rectangle().fill(.quaternary).aspectRatio(16 / 9, contentMode: .fit)
        if let p = clip.thumbnailPath, let img = NSImage(contentsOfFile: p) {
          Image(nsImage: img).resizable().scaledToFill().aspectRatio(16 / 9, contentMode: .fit)
            .clipped()
        } else {
          Image(systemName: "video").font(.largeTitle).foregroundStyle(.secondary)
        }
        if clip.previewUnavailable {
          Text("Preview unavailable").font(.caption2).padding(4).background(.black.opacity(0.6))
            .foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 4))
        }
      }
      Text(clip.currentFilename).lineLimit(1)
      HStack {
        Text(DurationFormatterUtil.string(clip.duration))
        Spacer()
        Text(clip.cullStatus.label)
        Text(clip.verificationStatus.rawValue)
      }.font(.caption).foregroundStyle(.secondary)
    }.padding(8).background(selected ? Color.accentColor.opacity(0.18) : Color.clear).clipShape(
      RoundedRectangle(cornerRadius: 10))
  }
}
