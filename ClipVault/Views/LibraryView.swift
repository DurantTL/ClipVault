import AppKit
import SwiftUI

struct LibraryView: View {
  @EnvironmentObject var settings: AppSettings
  @StateObject var viewModel: LibraryViewModel
  @State private var newFolder = ""
  @State private var showingSettings = false
  @State private var showingPreview = false
  @State private var showingBatchMetadata = false
  @State private var showingNewTagPrompt = false
  @State private var newTagName = ""
  @State private var showingAliasPrompt = false
  @State private var aliasFolderName = ""

  var body: some View {
    HSplitView {
      SidebarView(vm: viewModel, newFolder: $newFolder)
        .frame(minWidth: 200, idealWidth: 220, maxWidth: 260)
      VStack(spacing: 0) {
        if let operationError = viewModel.operationError {
          operationErrorBanner(operationError)
        }
        if viewModel.project.ingestStatus != .complete {
          partialBanner
        }
        if let progress = viewModel.exportProgress {
          exportBanner(progress)
        }
        if let summary = viewModel.exportSummary {
          exportSummaryBanner(summary)
        }
        if let summary = viewModel.aliasSummary {
          aliasSummaryBanner(summary)
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
    .toolbar { libraryToolbar }
    .sheet(isPresented: $showingSettings) { SettingsView() }
    .sheet(isPresented: $showingBatchMetadata) { BatchMetadataView(vm: viewModel) }
    .alert("New Tag", isPresented: $showingNewTagPrompt) {
      TextField("Tag name", text: $newTagName)
      Button("Add to Selection") {
        viewModel.addProductionTagToSelection(newTagName)
        newTagName = ""
      }
      Button("Cancel", role: .cancel) { newTagName = "" }
    } message: {
      Text("Adds this tag to every selected clip.")
    }
    .alert("Create Aliases", isPresented: $showingAliasPrompt) {
      TextField("Alias folder name", text: $aliasFolderName)
      Button("Create") {
        viewModel.createAliases(named: aliasFolderName)
        aliasFolderName = ""
      }
      Button("Cancel", role: .cancel) { aliasFolderName = "" }
    } message: {
      Text("Creates links in this project’s Aliases folder. Original copied media is never moved, deleted, or overwritten.")
    }
    .sheet(isPresented: $showingPreview) {
      PlayerPreviewView(
        library: viewModel,
        onClose: {
          viewModel.closePreview()
          showingPreview = false
        }
      )
    }
    .modifier(LibraryNotificationHandler(viewModel: viewModel, showingPreview: $showingPreview))
  }

  @ToolbarContentBuilder
  private var libraryToolbar: some ToolbarContent {
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
          ForEach(["All Clips"] + viewModel.smartFolders, id: \.self) { filter in
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
          Button("Select All Visible (⌘A)") { viewModel.selectAllVisible() }
          Button("Clear Multi-Selection (Esc)") { viewModel.clearMultiSelection() }
          Divider()
          Button("Mark selected as Keep") { viewModel.setStatus(.keep) }
          Button("Mark selected as Maybe") { viewModel.setStatus(.maybe) }
          Button("Mark selected as Reject") { viewModel.setStatus(.reject) }
          Button("Clear rating") { viewModel.setStatus(.unrated) }
          Menu("Set Rating") {
            ForEach([5, 4, 3, 2, 1, 0], id: \.self) { value in
              Button(value == 0 ? "0 — Unrated" : "\(value) \(String(repeating: "★", count: value))") {
                viewModel.setRating(value)
              }
            }
          }
          Divider()
          Menu("Add Tag") {
            ForEach(viewModel.productionTags, id: \.self) { tag in
              Button(tag) { viewModel.addProductionTagToSelection(tag) }
            }
            Divider()
            Button("New Tag…") { showingNewTagPrompt = true }
          }
          Menu("Remove Tag") {
            ForEach(viewModel.productionTagsInSelection, id: \.self) { tag in
              Button(tag) { viewModel.removeProductionTagFromSelection(tag) }
            }
          }
          Menu("Move to Folder") {
            ForEach(viewModel.project.customFolders, id: \.self) { folder in
              Button(folder) { viewModel.moveSelected(to: folder) }
            }
          }
          Button("Batch Edit Metadata…") { showingBatchMetadata = true }
          Button("Create Aliases…") { showingAliasPrompt = true }
          Button("Reveal Aliases in Finder") { viewModel.revealAliases() }
          Divider()
          Button("Copy filenames to clipboard") { viewModel.copySelectedFilenames() }
          Button("Reveal selected in Finder") { viewModel.reveal() }
          Divider()
          Button("Generate Missing Thumbnails") { viewModel.generateMissingThumbnails() }
          Button("Regenerate Thumbnail for This Clip") { viewModel.regenerateThumbnailForSelectedClip() }
          Button("Regenerate Thumbnails for Selected Clips") { viewModel.regenerateThumbnailsForSelectedClips() }
          Divider()
          Button("Find Duplicate Candidates") { viewModel.findDuplicateCandidates() }
          Button("Apply Suggested Ratings to Unrated Clips") { viewModel.applySuggestedRatingsToUnrated() }
        }

        Menu("Export") {
          Button("Copy Keeps to Edit Folder…") { viewModel.copyToEditFolder(.keeps) }
          Button("Copy Keep + Maybe to Edit Folder…") { viewModel.copyToEditFolder(.keepsAndMaybes) }
          Button("Copy 4–5 Star Clips to Edit Folder…") { viewModel.copyToEditFolder(.fourPlusStars) }
          Button("Copy Selected Clips to Folder…") { viewModel.copyToEditFolder(.selected) }
          Divider()
          Button("Export Clip Report CSV") { viewModel.exportClipReport(.allClips) }
          Button("Export Keep List CSV") { viewModel.exportClipReport(.keeps) }
          Button("Export Reject List CSV") { viewModel.exportClipReport(.rejects) }
          Button("Export Verification Report CSV") { viewModel.exportClipReport(.verification) }
          Button("Export Analysis Report CSV") { viewModel.exportClipReport(.analysis) }
          Button("Export Project Metadata JSON") { viewModel.exportProjectMetadata() }
          Divider()
          Button("Analyze Locally") { viewModel.analyzeLocally() }
          Divider()
          Button("Reveal an Edit Folder in Finder…") { EditFolderHandoff.chooseFolderAndHandOff(to: nil) }
          Button("Reveal Edit Folder + Open DaVinci Resolve…") {
            EditFolderHandoff.chooseFolderAndHandOff(to: "com.blackmagic-design.DaVinciResolve")
          }
          Button("Reveal Edit Folder + Open Final Cut Pro…") {
            EditFolderHandoff.chooseFolderAndHandOff(to: "com.apple.FinalCut")
          }
        }

        Button { showingSettings = true } label: {
          Label("Settings", systemImage: "gearshape")
        }
      }
    }

  private func exportBanner(_ progress: ClipExportProgress) -> some View {
    HStack(spacing: 12) {
      ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1)))
        .frame(maxWidth: 260)
      Text("Copying \(progress.completed + 1) of \(progress.total)\(progress.currentFilename.isEmpty ? "" : " — \(progress.currentFilename)")")
        .font(.caption)
        .lineLimit(1)
      Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(Color.blue.opacity(0.10))
  }

  private func exportSummaryBanner(_ summary: ClipExportSummary) -> some View {
    HStack(spacing: 12) {
      Label(summary.message, systemImage: summary.failedCount == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
        .font(.caption)
        .foregroundStyle(summary.failedCount == 0 ? Color.green : Color.orange)
        .lineLimit(2)
      Spacer()
      Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([summary.destination]) }
      Button("Dismiss") { viewModel.exportSummary = nil }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background((summary.failedCount == 0 ? Color.green : Color.orange).opacity(0.10))
  }

  private func aliasSummaryBanner(_ summary: AliasCreationSummary) -> some View {
    HStack(spacing: 12) {
      Label(summary.message, systemImage: summary.failedCount == 0 ? "link.circle.fill" : "exclamationmark.triangle.fill")
        .font(.caption)
        .foregroundStyle(summary.failedCount == 0 ? Color.accentColor : Color.orange)
        .lineLimit(2)
      Spacer()
      Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([summary.aliasesFolder]) }
      Button("Dismiss") { viewModel.aliasSummary = nil }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(Color.accentColor.opacity(0.10))
  }

  private func operationErrorBanner(_ message: String) -> some View {
    HStack(spacing: 12) {
      Label(message, systemImage: "exclamationmark.triangle.fill")
        .font(.caption)
        .foregroundStyle(.red)
        .lineLimit(3)
      Spacer()
      if viewModel.canRetryProjectSave {
        Button("Retry Project Save") { viewModel.retryProjectSave() }
      }
      if !viewModel.canRetryProjectSave {
        Button("Dismiss") { viewModel.dismissOperationError() }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(Color.red.opacity(0.10))
  }

  private var partialBanner: some View {
    HStack(spacing: 12) {
      Label(
        "Partial ingest — \(viewModel.project.copiedClipCount) of \(viewModel.project.totalSelectedClips) clips copied.",
        systemImage: "exclamationmark.triangle.fill"
      )
      .foregroundStyle(.orange)
      Spacer()
      if viewModel.isResumingIngest {
        ProgressView()
          .controlSize(.small)
      }
      Button("Resume Ingest") { viewModel.resumeIngest() }
        .disabled(viewModel.isResumingIngest)
      Button("Reveal Project Folder") { viewModel.revealProject() }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(Color.orange.opacity(0.12))
  }
}

private enum EditFolderHandoff {
  @MainActor
  static func chooseFolderAndHandOff(to applicationIdentifier: String?) {
    let panel = NSOpenPanel()
    panel.title = "Choose Edit Folder"
    panel.message = "Choose the folder \(AppBrand.appName) should reveal for your editing application."
    panel.prompt = applicationIdentifier == nil ? "Reveal" : "Reveal and Open App"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let folder = panel.url else { return }

    NSWorkspace.shared.activateFileViewerSelecting([folder])
    guard let applicationIdentifier else { return }
    guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: applicationIdentifier) else {
      showAlert(title: "Editor not found", message: "Install the selected editor, then try the handoff again.")
      return
    }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { _, error in
      guard let error else { return }
      DispatchQueue.main.async {
        showAlert(title: "Could not open editor", message: error.localizedDescription)
      }
    }
  }

  @MainActor
  private static func showAlert(title: String, message: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.runModal()
  }
}

private struct LibraryNotificationHandler: ViewModifier {
  @ObservedObject var viewModel: LibraryViewModel
  @Binding var showingPreview: Bool

  func body(content: Content) -> some View {
    content
      .onChange(of: viewModel.previewClip) { _, clip in showingPreview = clip != nil }
      .onReceive(NotificationCenter.default.publisher(for: .clipKeep)) { _ in viewModel.setRating(5) }
      .onReceive(NotificationCenter.default.publisher(for: .clipMaybe)) { _ in viewModel.setRating(3) }
      .onReceive(NotificationCenter.default.publisher(for: .clipReject)) { _ in viewModel.setRating(1) }
      .onReceive(NotificationCenter.default.publisher(for: .clipUnrated)) { _ in viewModel.setRating(0) }
      .onReceive(NotificationCenter.default.publisher(for: .clipRating2)) { _ in viewModel.setRating(2) }
      .onReceive(NotificationCenter.default.publisher(for: .clipRating4)) { _ in viewModel.setRating(4) }
      .onReceive(NotificationCenter.default.publisher(for: .clipReveal)) { _ in viewModel.reveal() }
      .onReceive(NotificationCenter.default.publisher(for: .clipPreview)) { _ in
        guard !showingPreview else { return }
        viewModel.previewSelected()
        showingPreview = viewModel.selectedClip != nil
      }
      .onReceive(NotificationCenter.default.publisher(for: .clipNext)) { _ in viewModel.selectNext() }
      .onReceive(NotificationCenter.default.publisher(for: .clipPrevious)) { _ in viewModel.selectPrevious() }
      .onReceive(NotificationCenter.default.publisher(for: .clipClosePreview)) { _ in
        viewModel.closePreview()
        showingPreview = false
      }
  }
}
