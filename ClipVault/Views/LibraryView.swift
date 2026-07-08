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
      ToolbarItemGroup {
        Button { showingIngest = true } label: {
          Label("New Ingest", systemImage: "tray.and.arrow.down.fill")
        }
        .buttonStyle(.borderedProminent)

        Button { viewModel.revealProject() } label: {
          Label("Open Library", systemImage: "folder")
        }

        Button { viewModel.reveal() } label: {
          Label("Reveal in Finder", systemImage: "arrow.up.forward.app")
        }

        Button { viewModel.undoMove() } label: {
          Label("Undo Last Move", systemImage: "arrow.uturn.backward")
        }
      }

      ToolbarItemGroup {
        Label("Thumbnail Size", systemImage: "rectangle.grid.2x2")
        Slider(value: $viewModel.thumbnailSize, in: 140...340)
          .frame(width: 160)
      }

      ToolbarItemGroup {
        Picker("Filter", selection: $viewModel.filter) {
          ForEach(["All Clips", "Unrated", "Keep", "Maybe", "Reject", "Verified", "Failed", "Has Audio", "No Audio", "4K", "60p", "Short Clip", "Long Clip"], id: \.self) { filter in
            Text(filter).tag(filter)
          }
        }
        .pickerStyle(.menu)

        Picker("Sort", selection: $viewModel.sortOption) {
          ForEach(ClipSortOption.allCases) { option in
            Text(option.rawValue).tag(option)
          }
        }
        .pickerStyle(.menu)

        Menu("Batch") {
          Button("Mark selected as Keep") { viewModel.setStatus(.keep) }
          Button("Mark selected as Maybe") { viewModel.setStatus(.maybe) }
          Button("Mark selected as Reject") { viewModel.setStatus(.reject) }
          Button("Clear rating") { viewModel.setStatus(.unrated) }
          Divider()
          Button("Copy filenames to clipboard") { viewModel.copySelectedFilenames() }
          Button("Reveal selected in Finder") { viewModel.reveal() }
        }

        Menu("Export") {
          Button("Export Clip Report CSV") { viewModel.exportClipReport() }
          Button("Export Keep List CSV") { viewModel.exportClipReport(keepsOnly: true) }
          Button("Export Project Metadata JSON") { viewModel.exportProjectMetadata() }
          Divider()
          Button("Analyze Locally") { viewModel.analyzeLocally() }
        }

        Button { showingSettings = true } label: {
          Label("Settings", systemImage: "gearshape")
        }
      }
    }
    .sheet(isPresented: $showingIngest) {
      NewIngestView { _ in }
        .frame(width: 900, height: 820)
    }
    .sheet(isPresented: $showingSettings) { SettingsView() }
    .sheet(item: $viewModel.previewClip) { clip in
      PlayerPreviewView(
        clip: clip,
        onClose: { viewModel.closePreview() },
        onNext: {
          viewModel.selectNext()
          viewModel.previewSelected()
        },
        onPrevious: {
          viewModel.selectPrevious()
          viewModel.previewSelected()
        }
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
