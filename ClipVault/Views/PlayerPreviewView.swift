import AVKit
import SwiftUI

struct PlayerPreviewView: View {
  @ObservedObject var library: LibraryViewModel
  let onClose: () -> Void
  @StateObject var vm = PlayerViewModel()

  private var clip: Clip? {
    library.selectedClipID.flatMap { id in
      library.filteredClips.first { $0.id == id } ?? library.project.clips.first { $0.id == id }
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(clip?.currentFilename ?? "No clip selected")
            .font(.headline)
          Text("Preview follows the current library selection")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button("Previous", action: library.selectPrevious)
        Button("Next", action: library.selectNext)
        Button("Close", action: onClose)
          .keyboardShortcut(.escape)
      }
      .padding()

      if let clip {
        if clip.previewUnavailable {
          ContentUnavailableView(
            "Copied and verified — preview unavailable on this Mac.",
            systemImage: "video.slash"
          )
          .frame(minWidth: 800, minHeight: 500)
        } else {
          AVPlayerViewRepresented(player: vm.player)
            .frame(minWidth: 800, minHeight: 500)
        }
      } else {
        ContentUnavailableView("No clip selected", systemImage: "film")
          .frame(minWidth: 800, minHeight: 500)
      }
    }
    .background(KeyboardShortcutCatcher { event in
      switch event.keyCode {
      case 53:
        onClose()
        return true
      case 49:
        vm.togglePlayPause()
        return true
      case 123:
        library.selectPrevious()
        return true
      case 124:
        library.selectNext()
        return true
      default:
        return false
      }
    }.frame(width: 0, height: 0))
    .onAppear { loadActiveClip(autoplay: true) }
    .onChange(of: library.selectedClipID) {
      loadActiveClip(autoplay: true)
    }
    .onDisappear { vm.stop() }
  }

  private func loadActiveClip(autoplay: Bool) {
    guard let clip else {
      vm.stop()
      return
    }
    if clip.previewUnavailable {
      vm.stop()
    } else {
      vm.load(clip)
      if autoplay { vm.player?.play() }
    }
  }
}

struct AVPlayerViewRepresented: NSViewRepresentable {
  let player: AVPlayer?

  func makeNSView(context: Context) -> AVPlayerView {
    let view = AVPlayerView()
    view.controlsStyle = .floating
    return view
  }

  func updateNSView(_ nsView: AVPlayerView, context: Context) {
    nsView.player = player
  }
}
