import AppKit
import SwiftUI

struct LibraryView: View {
  @EnvironmentObject var settings: AppSettings
  @StateObject var viewModel: LibraryViewModel
  @State private var newFolder = ""
  @State private var showingSettings = false
  @State private var showingPreview = false

  var body: some View {
    HSplitView {
      SidebarView(vm: viewModel, newFolder: $newFolder)
        .frame(minWidth: 200, idealWidth: 220, maxWidth: 260)
      VStack(spacing: 0) {
        if viewModel.project.ingestStatus != .complete {
          partialBanner
        }
        ClipGridView(vm: viewModel)
          .frame(minWidth: 650, maxWidth: .infinity, maxHeight: .infinity)
      }
      .frame(minWidth: 650, maxWidth: .infinity)
      if viewModel.inspectorVisible {
        ClipInspectorView(clip: viewModel.selectedClip, vm: viewModel)
          .frame(minWidth: 300, idealWidth: 340, maxWidth: 390)
      }
    }
    .toolbar {
      ToolbarItemGroup {
        Button { NewIngestWindowManager.shared.open(settings: settings) { project in viewModel.project = project } } label: {
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

        Toggle(isOn: $viewModel.sortAscending) {
          Label(viewModel.sortAscending ? "Ascending" : "Descending", systemImage: "arrow.up.arrow.down")
        }

        Button { viewModel.inspectorVisible.toggle() } label: {
          Label(viewModel.inspectorVisible ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.right")
        }

        Menu("Batch") {
          Button("Mark selected as Keep") { viewModel.setStatus(.keep) }
          Button("Mark selected as Maybe") { viewModel.setStatus(.maybe) }
          Button("Mark selected as Reject") { viewModel.setStatus(.reject) }
          Button("Clear rating") { viewModel.setStatus(.unrated) }
          Divider()
          Button("Copy filenames to clipboard") { viewModel.copySelectedFilenames() }
          Button("Reveal selected in Finder") { viewModel.reveal() }
          Divider()
          Button("Generate Missing Thumbnails") { viewModel.generateMissingThumbnails() }
          Button("Regenerate Thumbnail for This Clip") { viewModel.regenerateThumbnailForSelectedClip() }
          Button("Regenerate Thumbnails for Selected Clips") { viewModel.regenerateThumbnailsForSelectedClips() }
          Divider()
          Button("Find Duplicate Candidates") { viewModel.findDuplicateCandidates() }
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
    .sheet(isPresented: $showingSettings) { SettingsView() }
    .sheet(isPresented: $showingPreview) {
      PlayerPreviewView(
        library: viewModel,
        onClose: {
          viewModel.closePreview()
          showingPreview = false
        }
      )
    }
    .onChange(of: viewModel.previewClip) { _, clip in
      showingPreview = clip != nil
    }
    .onReceive(NotificationCenter.default.publisher(for: .clipKeep)) { _ in viewModel.setStatus(.keep) }
    .onReceive(NotificationCenter.default.publisher(for: .clipMaybe)) { _ in viewModel.setStatus(.maybe) }
    .onReceive(NotificationCenter.default.publisher(for: .clipReject)) { _ in viewModel.setStatus(.reject) }
    .onReceive(NotificationCenter.default.publisher(for: .clipUnrated)) { _ in viewModel.setStatus(.unrated) }
    .onReceive(NotificationCenter.default.publisher(for: .clipReveal)) { _ in viewModel.reveal() }
    .onReceive(NotificationCenter.default.publisher(for: .clipPreview)) { _ in
      if showingPreview {
        // Space toggles playback inside PlayerPreviewView; keep the preview selection-bound.
      } else {
        viewModel.previewSelected()
        showingPreview = viewModel.selectedClip != nil
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .clipNext)) { _ in viewModel.selectNext() }
    .onReceive(NotificationCenter.default.publisher(for: .clipPrevious)) { _ in viewModel.selectPrevious() }
    .onReceive(NotificationCenter.default.publisher(for: .clipClosePreview)) { _ in
      viewModel.closePreview()
      showingPreview = false
    }
  }

  private var partialBanner: some View {
    HStack(spacing: 12) {
      Label(
        "Partial ingest — \(viewModel.project.copiedClipCount) of \(viewModel.project.totalSelectedClips) clips copied.",
        systemImage: "exclamationmark.triangle.fill"
      )
      .foregroundStyle(.orange)
      Spacer()
      Button("Resume Ingest") { viewModel.resumeIngest() }
      Button("Retry Failed") { viewModel.resumeIngest() }
      Button("Reveal Project Folder") { viewModel.revealProject() }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(Color.orange.opacity(0.12))
  }
}
