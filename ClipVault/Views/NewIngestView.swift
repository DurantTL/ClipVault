import SwiftUI

struct NewIngestView: View {
  @EnvironmentObject var settings: AppSettings
  @Environment(\.dismiss) var dismiss
  @StateObject var vm = NewIngestViewModel()
  let openProject: (ClipVaultProject) -> Void
  var total: Int64 { vm.videos.reduce(0) { $0 + $1.size } }
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("New Ingest").font(.largeTitle.bold())
      HStack {
        Button("Choose Source") { vm.chooseSource(settings: settings) }
        Text(vm.sourceURL?.path ?? "No source selected").lineLimit(1)
      }
      HStack {
        Button("Choose Destination") { vm.chooseDestination() }
        Text(vm.destinationURL?.path ?? "No destination selected").lineLimit(1)
      }
      TextField("Project name", text: $vm.projectName).textFieldStyle(.roundedBorder)
      Toggle("Include Sony proxy files from PRIVATE/M4ROOT/SUB", isOn: $settings.includeProxyFiles)
        .onChange(of: settings.includeProxyFiles) { vm.scan(settings: settings) }
      GroupBox("Scan Result") {
        HStack {
          Text("\(vm.videos.count) videos")
          Spacer()
          Text(FileSizeFormatterUtil.string(total))
        }
        Text(
          "Sony cards are scanned recursively; PRIVATE/M4ROOT/CLIP is prioritized and proxy SUB files are skipped by default."
        ).font(.caption).foregroundStyle(.secondary)
      }
      if vm.isIngesting {
        IngestProgressView(progress: vm.progress)
        Button("Cancel Ingest") { vm.ingestService.cancel() }
      } else {
        Button("Start Copy") {
          Task {
            if let p = await vm.start(settings: settings) {
              dismiss()
              openProject(p)
            }
          }
        }.buttonStyle(.borderedProminent).disabled(vm.videos.isEmpty || vm.destinationURL == nil)
      }
      if let e = vm.error { Text(e).foregroundStyle(.red) }
      Spacer()
    }.padding(24)
  }
}
