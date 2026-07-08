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
      ScrollView {
        LazyVGrid(columns: columns, spacing: 16) {
          ForEach(vm.filteredClips) { clip in
            ClipCardView(
              clip: clip,
              selected: vm.selectedClipIDs.contains(clip.id),
              preview: {
                vm.select(clip)
                vm.previewSelected()
              },
              rate: { status in
                vm.select(clip)
                vm.setStatus(status)
              }
            )
              .onTapGesture { vm.select(clip) }
              .onTapGesture(count: 2) {
                vm.select(clip)
                vm.previewSelected()
              }
              .draggable(clip)
          }
        }
        .padding()
      }
    }
    .background(KeyboardShortcutCatcher { event in handle(event) }.frame(width: 0, height: 0))
    .focusable()
    .onDeleteCommand { vm.setStatus(.reject) }
  }

  private func handle(_ event: NSEvent) -> Bool {
    if NSApp.keyWindow?.firstResponder is NSTextView { return false }
    if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "r" {
      vm.reveal()
      return true
    }
    switch event.keyCode {
    case 49:
      vm.previewSelected()
    case 53:
      vm.closePreview()
    case 124:
      vm.selectNext()
    case 123:
      vm.selectPrevious()
    default:
      switch event.charactersIgnoringModifiers {
      case "5": vm.setStatus(.keep)
      case "3": vm.setStatus(.maybe)
      case "1": vm.setStatus(.reject)
      case "0": vm.setStatus(.unrated)
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
      Text("5 Keep")
      Text("3 Maybe")
      Text("1 Reject")
      Text("0 Clear")
      Text("←/→ Select")
      Text("⌘R Reveal")
      Text("Esc Close")
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
