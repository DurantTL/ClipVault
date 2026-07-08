import SwiftUI

struct HomeView: View {
  @StateObject var vm = HomeViewModel()
  @State private var showingIngest = false
  let openProject: (ClipVaultProject) -> Void

  var body: some View {
    NavigationSplitView {
      List {
        Section { Text("Home") }
        Section("Recent Projects") { ForEach(vm.summaries) { Text($0.name) } }
        Section("All Projects") { ForEach(groupedMonths, id: \.self) { Text($0) } }
      }
      .navigationTitle("ClipVault")
    } detail: {
      ScrollView {
        VStack(spacing: 24) {
          Image(systemName: "play.rectangle.on.rectangle.circle.fill")
            .font(.system(size: 72))
            .foregroundStyle(.blue)
          Text("ClipVault").font(.largeTitle.bold())
          Text("Copy. Verify. Cull. Organize.").font(.title3).foregroundStyle(.secondary)
          HStack {
            Button("New Ingest") { showingIngest = true }
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
    .sheet(isPresented: $showingIngest) {
      NewIngestView(openProject: openProject).frame(width: 860, height: 760)
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
        if let path = summary.coverThumbnail, let image = NSImage(contentsOfFile: path) {
          Image(nsImage: image).resizable().scaledToFill().clipped()
        } else {
          Image(systemName: "film.stack").font(.largeTitle).foregroundStyle(.secondary)
        }
      }
      Text(summary.name).font(.headline).lineLimit(1)
      Text("\(summary.clipCount) clips • \(FileSizeFormatterUtil.string(summary.totalSize))")
      Text("Keep \(summary.kept)  Maybe \(summary.maybe)  Reject \(summary.rejected)")
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
    .background(Color(nsColor: .controlBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 14))
  }

  private func date(_ date: Date?) -> String {
    guard let date else { return "—" }
    return date.formatted(date: .abbreviated, time: .omitted)
  }
}
