import AVKit
import SwiftUI

struct PlayerPreviewView: View {
  let clip: Clip
  let onClose: () -> Void
  let onNext: () -> Void
  let onPrevious: () -> Void
  @StateObject var vm = PlayerViewModel()

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(clip.currentFilename).font(.headline)
        Spacer()
        Button("Previous", action: onPrevious)
        Button("Next", action: onNext)
        Button("Close", action: onClose).keyboardShortcut(.escape)
      }
      .padding()
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
    }
    .background(KeyboardShortcutCatcher { event in
      if event.keyCode == 53 {
        onClose()
        return true
      }
      if event.keyCode == 49 {
        vm.togglePlayPause()
        return true
      }
      return false
    }.frame(width: 0, height: 0))
    .onAppear {
      vm.load(clip)
      vm.player?.play()
    }
    .onDisappear { vm.player?.pause() }
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
