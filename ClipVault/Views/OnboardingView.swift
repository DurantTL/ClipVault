import SwiftUI

/// First-launch walkthrough of the core workflow. Re-openable any time from
/// Help → Welcome. Completion only flips a UserDefaults flag; onboarding never
/// touches projects or media.
struct OnboardingView: View {
  var finish: () -> Void

  @State private var pageIndex = 0

  private struct Page {
    let systemImage: String
    let title: String
    let message: String
  }

  private let pages: [Page] = [
    Page(
      systemImage: "rectangle.stack.badge.play",
      title: "Welcome to \(AppBrand.appName)",
      message: "\(AppBrand.tagline)\n\nA daily project-based workflow for your footage: copy from the card, verify the copy, cull fast, and hand the keepers to your editor. \(AppBrand.appName) never deletes, modifies, or writes to your camera cards."
    ),
    Page(
      systemImage: "sdcard",
      title: "Ingest safely",
      message: "Click New Ingest and pick a card or folder. Sony PRIVATE/M4ROOT/CLIP and Canon DCIM layouts are detected automatically. Files stream to your destination in chunks, with pause, resume, and cancel — and canceled ingests always reopen."
    ),
    Page(
      systemImage: "checkmark.seal",
      title: "Verify the copy",
      message: "Every copied file is verified before it counts — a fast size check by default, or strong SHA256 in Settings. Optional Backup 1 and Backup 2 destinations are copied from the verified primary so the card is read once."
    ),
    Page(
      systemImage: "star",
      title: "Cull at keyboard speed",
      message: "Space previews. 1–5 set a star rating (5 = best keep, 1 = reject), 0 clears it. Arrow keys move between clips, and ratings sync with Keep / Maybe / Reject so your filters always agree with your stars."
    ),
    Page(
      systemImage: "square.and.arrow.up",
      title: "Export and hand off",
      message: "Copy your Keeps to an edit folder — never moved, never overwritten — then open it in Finder, DaVinci Resolve, or Final Cut Pro. CSV reports and project metadata JSON travel with the footage."
    )
  ]

  var body: some View {
    VStack(spacing: 24) {
      Image(systemName: pages[pageIndex].systemImage)
        .font(.system(size: 56, weight: .medium))
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(.tint)
        .frame(height: 72)

      Text(pages[pageIndex].title)
        .font(.title.bold())
        .multilineTextAlignment(.center)

      Text(pages[pageIndex].message)
        .font(.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 440)
        .frame(minHeight: 130, alignment: .top)

      HStack(spacing: 8) {
        ForEach(pages.indices, id: \.self) { index in
          Circle()
            .fill(index == pageIndex ? Color.accentColor : Color.secondary.opacity(0.3))
            .frame(width: 8, height: 8)
        }
      }

      HStack {
        Button("Skip") { finish() }
          .buttonStyle(.plain)
          .foregroundStyle(.secondary)
        Spacer()
        if pageIndex > 0 {
          Button("Back") { pageIndex -= 1 }
        }
        if pageIndex < pages.count - 1 {
          Button("Continue") { pageIndex += 1 }
            .keyboardShortcut(.defaultAction)
        } else {
          Button("Get Started") { finish() }
            .keyboardShortcut(.defaultAction)
        }
      }
      .frame(maxWidth: 440)
    }
    .padding(40)
    .frame(width: 560, height: 480)
  }
}
