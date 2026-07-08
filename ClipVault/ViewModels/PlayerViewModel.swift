import Foundation
import AVKit
final class PlayerViewModel: ObservableObject { @Published var player: AVPlayer?; func load(_ clip: Clip) { player = AVPlayer(url: URL(fileURLWithPath: clip.currentPath)) } }
