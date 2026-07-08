import SwiftUI
import AVKit
struct PlayerPreviewView: View { let clip: Clip; @StateObject var vm = PlayerViewModel(); var body: some View { VStack { AVPlayerViewRepresented(player: vm.player).frame(minWidth:800,minHeight:500); Text(clip.currentFilename).padding(.bottom) }.onAppear{vm.load(clip); vm.player?.play()} } }
struct AVPlayerViewRepresented: NSViewRepresentable { let player: AVPlayer?; func makeNSView(context:Context)->AVPlayerView{ let v=AVPlayerView(); v.controlsStyle = .floating; return v }; func updateNSView(_ nsView:AVPlayerView, context:Context){ nsView.player = player } }
