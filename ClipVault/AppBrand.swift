import SwiftUI

struct AppBrand {
  // MARK: User-visible brand — update these when the product is renamed.
  //
  // Rename checklist for items that cannot flow through this file:
  // - SlateBox.xcodeproj/project.pbxproj: PRODUCT_NAME, INFOPLIST_KEY_CFBundleDisplayName,
  //   INFOPLIST_KEY_NSRemovableVolumesUsageDescription text, bundle IDs (com.slatebox.mac / .tests)
  // - Xcode scheme name (SlateBox)
  // - .github/workflows/build.yml scheme/name references
  // - README.md, ROADMAP.md, TESTING.md titles and prose
  static let appName = "SlateBox"
  static let tagline = "Ingest. Verify. Cull. Hand off."

  // MARK: Stable on-disk / internal identifiers — NEVER change these on a rename.
  //
  // These are permanent format identifiers, independent of the product name.
  // Existing projects on user disks must remain openable forever (safety rule 14),
  // so the legacy "clipvault" spelling is intentional and load-bearing.
  static let metadataFileName = ".clipvault-project.json"
  static let cacheFolderName = ".clipvault-cache"
  static let partialFileSuffix = ".clipvault-partial"
  static let partialManifestSuffix = ".clipvault-partial.json"
  static let previewCacheFolderName = "ClipVault"
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
    .accessibilityLabel("\(AppBrand.appName) logo")
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
