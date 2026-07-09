import AppKit
import SwiftUI

struct ClipGridView: View {
  @ObservedObject var vm: LibraryViewModel

  var columns: [GridItem] {
    [GridItem(.adaptive(minimum: vm.thumbnailSize), spacing: 16)]
  }

  var body: some View {
    VStack(spacing: 0) {
      KeyboardLegend(autoAdvance: AppSettings.autoAdvanceAfterRating)
      if vm.selectedClipIDs.count > 1 {
        selectionBar
      }
      ScrollView {
        LazyVGrid(columns: columns, spacing: 16) {
          ForEach(vm.filteredClips) { clip in
            ClipCardView(
              clip: clip,
              selected: vm.selectedClipIDs.contains(clip.id),
              canPreview: vm.canPreview(clip),
              thumbnailURL: vm.existingThumbnailURL(for: clip),
              preview: {
                vm.select(clip)
                vm.previewSelected()
              },
              rate: { rating in
                if !vm.selectedClipIDs.contains(clip.id) { vm.select(clip) } else { vm.selectedClipID = clip.id }
                vm.setRating(rating)
              }
            )
              .onTapGesture { handleTap(on: clip) }
              .onTapGesture(count: 2) {
                vm.select(clip)
                vm.previewSelected()
              }
              .draggable(clip)
              .onAppear { vm.queueThumbnailGenerationIfNeeded(for: clip) }
              .contextMenu {
                Button("Regenerate Thumbnail for This Clip") {
                  vm.select(clip)
                  vm.regenerateThumbnailForSelectedClip()
                }
                Button("Regenerate Thumbnails for Selected Clips") {
                  vm.regenerateThumbnailsForSelectedClips()
                }
              }
          }
        }
        .padding()
      }
    }
    .background(KeyboardShortcutCatcher { event in handle(event) }.frame(width: 0, height: 0))
    .focusable()
    .onDeleteCommand { vm.setStatus(.reject) }
  }

  private var selectionBar: some View {
    HStack(spacing: 12) {
      Label("\(vm.selectedClipIDs.count) clips selected", systemImage: "checkmark.circle.fill")
        .font(.caption.bold())
      Spacer()
      Button("Clear Selection (Esc)") { vm.clearMultiSelection() }
        .controlSize(.small)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(Color.accentColor.opacity(0.12))
  }

  private func handleTap(on clip: Clip) {
    let modifiers = NSEvent.modifierFlags
    if modifiers.contains(.shift) {
      vm.selectRange(to: clip)
    } else if modifiers.contains(.command) {
      vm.select(clip, extending: true)
    } else {
      vm.select(clip)
    }
  }

  private func handle(_ event: NSEvent) -> Bool {
    if NSApp.keyWindow?.firstResponder is NSTextView { return false }
    if event.modifierFlags.contains(.command) {
      switch event.charactersIgnoringModifiers?.lowercased() {
      case "r":
        vm.reveal()
        return true
      case "a":
        vm.selectAllVisible()
        return true
      default:
        return false
      }
    }
    switch event.keyCode {
    case 49:
      vm.previewSelected()
    case 53:
      if vm.previewClip != nil {
        vm.closePreview()
      } else {
        vm.clearMultiSelection()
      }
    case 124:
      vm.selectNext()
    case 123:
      vm.selectPrevious()
    default:
      switch event.charactersIgnoringModifiers {
      case "0", "1", "2", "3", "4", "5":
        guard let value = event.charactersIgnoringModifiers.flatMap({ Int($0) }) else { return false }
        vm.setRating(value)
      default: return false
      }
    }
    return true
  }
}

struct KeyboardLegend: View {
  let autoAdvance: Bool

  var body: some View {
    HStack(spacing: 14) {
      Label("Space Preview", systemImage: "space")
      Text("1–5 Rate (5★ Keep · 3★ Maybe · 1★ Reject)")
      Text("0 Clear")
      Text("←/→ Select")
      Text("⌘-Click Add")
      Text("⇧-Click Range")
      Text("⌘A All")
      Text("⌘R Reveal")
      Text("Esc Close/Clear")
      if autoAdvance {
        Label("Auto-advance: On", systemImage: "forward.fill")
          .foregroundStyle(.blue)
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.thinMaterial)
  }
}
