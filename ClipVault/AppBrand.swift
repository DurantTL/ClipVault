import SwiftUI

struct AppBrand {
  static let appName = "ClipVault"
  static let tagline = "Copy. Verify. Cull. Organize."
  static let metadataFileName = ".clipvault-project.json"
  static let cacheFolderName = ".clipvault-cache"
}

struct LogoMarkView: View {
  var size: CGFloat = 72

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
        .fill(
          LinearGradient(
            colors: [Color.blue, Color.purple.opacity(0.90)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
        .overlay(
          RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .stroke(.white.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .blue.opacity(0.22), radius: size * 0.16, y: size * 0.08)

      Image(systemName: "rectangle.stack.badge.play")
        .font(.system(size: size * 0.42, weight: .semibold))
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(.white)

      Image(systemName: "checkmark.seal.fill")
        .font(.system(size: size * 0.22, weight: .bold))
        .foregroundStyle(.green, .white)
        .background(Circle().fill(.white.opacity(0.9)))
        .offset(x: size * 0.28, y: size * 0.27)
    }
    .frame(width: size, height: size)
    .accessibilityLabel("ClipVault logo")
  }
}

struct AppHeaderView: View {
  var subtitle: String = AppBrand.tagline
  var logoSize: CGFloat = 64

  var body: some View {
    HStack(spacing: 16) {
      LogoMarkView(size: logoSize)

      VStack(alignment: .leading, spacing: 4) {
        Text(AppBrand.appName)
          .font(.largeTitle.bold())
        Text(subtitle)
          .font(.title3)
          .foregroundStyle(.secondary)
      }
    }
  }
}

struct CardContainer<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .padding(16)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .stroke(.quaternary, lineWidth: 1)
      )
  }
}
