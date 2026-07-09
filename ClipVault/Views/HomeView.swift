import SwiftUI

struct HomeView: View {
  @EnvironmentObject var settings: AppSettings
  @StateObject var vm = HomeViewModel()
  let openProject: (ClipVaultProject) -> Void

  var body: some View {
    NavigationSplitView {
      List {
        Section { Text("Home") }
        Section("Recent Projects") { ForEach(vm.summaries) { Text($0.name) } }
        Section("All Projects") { ForEach(groupedMonths, id: \.self) { Text($0) } }
      }
      .navigationTitle(AppBrand.appName)
    } detail: {
      ScrollView {
        VStack(spacing: 24) {
          LogoMarkView(size: 96)
          Text(AppBrand.appName).font(.largeTitle.bold())
          Text(AppBrand.tagline).font(.title3).foregroundStyle(.secondary)
          HStack {
            Button("New Ingest") { NewIngestWindowManager.shared.open(settings: settings, openProject: openProject) }
              .buttonStyle(.borderedProminent)
              .controlSize(.large)
            Button("Open Existing Project") { if let project = vm.pickProject() { openProject(project) } }
              .controlSize(.large)
            Menu("Open Recent") {
              ForEach(vm.summaries) { summary in
                Button(summary.name) { if let project = vm.loadRecent(path: summary.path) { openProject(project) } }
              }
            }
            .controlSize(.large)
          }
          if let error = vm.error { Text(error).foregroundStyle(.red).multilineTextAlignment(.center) }
          if vm.summaries.isEmpty {
            CardContainer {
              ContentUnavailableView(
                "No projects yet",
                systemImage: "externaldrive.badge.plus",
                description: Text("Start by ingesting footage from an SD card or folder.")
              )
            }
          }
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 18)], spacing: 18) {
            ForEach(vm.summaries) { summary in
              ProjectCard(summary: summary, open: {
                if let project = vm.loadRecent(path: summary.path) { openProject(project) }
              }, reveal: {
                vm.reveal(path: summary.path)
              }, remove: {
                vm.removeRecent(path: summary.path)
              })
            }
          }
        }
        .padding(36)
      }
    }
  }

  var groupedMonths: [String] {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMMM yyyy"
    return Array(Set(vm.summaries.compactMap { $0.createdAt.map(formatter.string(from:)) })).sorted()
  }
}

struct ProjectCard: View {
  let summary: RecentProjectSummary
  let open: () -> Void
  let reveal: () -> Void
  let remove: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ZStack {
        Rectangle().fill(.quaternary).aspectRatio(16 / 9, contentMode: .fit)
        if let url = resolvedCoverThumbnailURL(for: summary), let image = NSImage(contentsOf: url) {
          Image(nsImage: image).resizable().scaledToFill().clipped()
        } else {
          Image(systemName: "film.stack").font(.largeTitle).foregroundStyle(.secondary)
        }
      }
      Text(summary.name).font(.headline).lineLimit(1)
      Text("\(summary.clipCount) clips • \(FileSizeFormatterUtil.string(summary.totalSize))")
      Text("Keep \(summary.kept)  Maybe \(summary.maybe)  Reject \(summary.rejected)")
      Text("Status: \(summary.statusLabel)")
        .font(.caption.bold())
        .foregroundStyle(summary.isPartial ? Color.orange : Color.secondary)
      Text("Created \(date(summary.createdAt)) • Opened \(date(summary.lastOpenedAt))")
        .font(.caption)
        .foregroundStyle(.secondary)
      HStack {
        Button("Open", action: open)
        Menu("More") {
          Button("Reveal in Finder", action: reveal)
          Button("Remove from Recent", action: remove)
        }
      }
    }
    .padding()
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.quaternary))
  }

  private func resolvedCoverThumbnailURL(for summary: RecentProjectSummary) -> URL? {
    guard let thumbnailPath = summary.coverThumbnail, !thumbnailPath.isEmpty else {
      return nil
    }

    let thumbnailURL = URL(fileURLWithPath: thumbnailPath)
    if thumbnailURL.path.hasPrefix("/") {
      return FileManager.default.fileExists(atPath: thumbnailURL.path) ? thumbnailURL : nil
    }

    guard let projectFolderPath = summary.projectFolderPath else {
      return nil
    }

    let projectFolderURL = URL(fileURLWithPath: projectFolderPath, isDirectory: true)
    let resolvedURL = projectFolderURL.appendingPathComponent(thumbnailPath)
    return FileManager.default.fileExists(atPath: resolvedURL.path) ? resolvedURL : nil
  }

  private func date(_ date: Date?) -> String {
    guard let date else { return "—" }
    return date.formatted(date: .abbreviated, time: .omitted)
  }
}
