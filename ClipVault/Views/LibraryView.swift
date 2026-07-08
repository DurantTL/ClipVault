import SwiftUI

struct LibraryView: View {
  @StateObject var viewModel: LibraryViewModel
  @State private var newFolder = ""
  @State private var showingIngest = false
  @State private var showingSettings = false

  var body: some View {
    NavigationSplitView {
      SidebarView(vm: viewModel, newFolder: $newFolder)
    } content: {
      ClipGridView(vm: viewModel)
    } detail: {
      ClipInspectorView(clip: viewModel.selectedClip, vm: viewModel)
    }
    .toolbar {
      Button("New Ingest") { showingIngest = true }
      Button("Open Library") {}
      Button("Reveal in Finder") { viewModel.reveal() }
      Button("Undo Last Move") { viewModel.undoMove() }
      Slider(value: $viewModel.thumbnailSize, in: 130...320) { Text("Thumbnail Size") }
        .frame(width: 160)
      Menu("Filter") {
        ForEach(["All Clips", "Unrated", "Keep", "Maybe", "Reject"], id: \.self) { filter in
          Button(filter) { viewModel.filter = filter }
        }
      }
      Button("Settings") { showingSettings = true }
    }
    .sheet(isPresented: $showingIngest) {
      NewIngestView { _ in }.frame(width: 860, height: 760)
    }
    .sheet(isPresented: $showingSettings) { SettingsView() }
    .sheet(item: $viewModel.previewClip) { clip in
      PlayerPreviewView(
        clip: clip,
        onClose: { viewModel.closePreview() },
        onNext: { viewModel.selectNext(); viewModel.previewSelected() },
        onPrevious: { viewModel.selectPrevious(); viewModel.previewSelected() }
      )
    }
    .onReceive(NotificationCenter.default.publisher(for: .clipKeep)) { _ in viewModel.setStatus(.keep) }
    .onReceive(NotificationCenter.default.publisher(for: .clipMaybe)) { _ in viewModel.setStatus(.maybe) }
    .onReceive(NotificationCenter.default.publisher(for: .clipReject)) { _ in viewModel.setStatus(.reject) }
    .onReceive(NotificationCenter.default.publisher(for: .clipUnrated)) { _ in viewModel.setStatus(.unrated) }
    .onReceive(NotificationCenter.default.publisher(for: .clipReveal)) { _ in viewModel.reveal() }
    .onReceive(NotificationCenter.default.publisher(for: .clipPreview)) { _ in viewModel.previewSelected() }
    .onReceive(NotificationCenter.default.publisher(for: .clipNext)) { _ in viewModel.selectNext() }
    .onReceive(NotificationCenter.default.publisher(for: .clipPrevious)) { _ in viewModel.selectPrevious() }
    .onReceive(NotificationCenter.default.publisher(for: .clipClosePreview)) { _ in viewModel.closePreview() }
  }
}
