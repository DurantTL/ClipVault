import SwiftUI

struct HomeView: View {
  @StateObject var vm = HomeViewModel()
  @State private var showingIngest = false
  let openProject: (ClipVaultProject) -> Void
  var body: some View {
    VStack(spacing: 24) {
      Image(systemName: "shippingbox.and.arrow.backward").font(.system(size: 64)).foregroundStyle(
        .blue)
      Text("ClipVault").font(.largeTitle.bold())
      Text("Safe video ingest, preview, culling, and folder sorting for macOS.").foregroundStyle(
        .secondary)
      HStack {
        Button("New Ingest") { showingIngest = true }.buttonStyle(.borderedProminent).controlSize(
          .large)
        Button("Open Existing Project") { if let p = vm.pickProject() { openProject(p) } }
          .controlSize(.large)
      }
      if let e = vm.error { Text(e).foregroundStyle(.red).multilineTextAlignment(.center) }
      if !vm.recentProjects.isEmpty {
        List(vm.recentProjects, id: \.self) { path in
          Button(path) { if let p = vm.loadRecent(path: path) { openProject(p) } }
        }.frame(maxHeight: 180)
      }
    }.padding(50).sheet(isPresented: $showingIngest) {
      NewIngestView(openProject: openProject).frame(width: 760, height: 620)
    }
  }
}
