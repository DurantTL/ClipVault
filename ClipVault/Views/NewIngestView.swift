import SwiftUI

struct NewIngestView: View {
  @EnvironmentObject var settings: AppSettings
  @Environment(\.dismiss) var dismiss
  @StateObject var vm = NewIngestViewModel()
  let openProject: (ClipVaultProject) -> Void
  var total: Int64 { vm.videos.reduce(0) { $0 + $1.size } }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Text("New Ingest").font(.largeTitle.bold())
        GroupBox("Source/Card") {
          HStack {
            Button("Choose Source") { vm.chooseSource(settings: settings) }
            Text(vm.sourceURL?.path ?? "No source selected").lineLimit(1)
          }
          if vm.isSonyCard { Label("Sony card detected: PRIVATE/M4ROOT/CLIP", systemImage: "checkmark.seal.fill") }
        }
        GroupBox("Destination") {
          HStack {
            Button("Choose Destination") { vm.chooseDestination() }
            Text(vm.destinationURL?.path ?? "No destination selected").lineLimit(1)
          }
          TextField("Project Folder Name", text: $vm.projectName).textFieldStyle(.roundedBorder)
          TextField("Shoot/Subfolder Name (optional, e.g. Shoot 1, Sermon, Interviews, B-Roll)", text: $vm.shootName)
            .textFieldStyle(.roundedBorder)
          Text("Final Output: \(vm.finalOutputURL?.path ?? "Choose a destination")")
            .font(.caption)
            .textSelection(.enabled)
          HStack {
            Button("Create Project Folder") { vm.createProjectFolder() }
            Button("Reveal Destination") { vm.revealDestination() }
          }
        }
        GroupBox("Ingest Options") {
          Picker("Folder Structure Mode", selection: $settings.preserveSourceStructure) {
            Text("Flat").tag(false)
            Text("Preserve Source Structure").tag(true)
          }
          Toggle("Include Sony proxy files from PRIVATE/M4ROOT/SUB", isOn: $settings.includeProxyFiles)
            .onChange(of: settings.includeProxyFiles) { vm.scan(settings: settings) }
          Picker("Verification Mode", selection: $settings.verificationModeRaw) {
            ForEach(VerificationMode.allCases) { Text($0.label).tag($0.rawValue) }
          }
          Text("Strong is safer but slower for large 4K footage.")
            .font(.caption)
            .foregroundStyle(.secondary)
          Picker("Thumbnail Quality", selection: $settings.thumbnailQualityRaw) {
            ForEach(ThumbnailQuality.allCases) { Text($0.rawValue.capitalized).tag($0.rawValue) }
          }
        }
        GroupBox("Scan Result") {
          HStack {
            Text("\(vm.videos.count) videos")
            Spacer()
            Text(FileSizeFormatterUtil.string(total))
          }
          if let free = vm.destinationFreeSpace {
            Text("Estimated destination free space: \(FileSizeFormatterUtil.string(free))")
            if free < total { Text("Warning: destination free space may be too low.").foregroundStyle(.red) }
          }
          Text(vm.isSonyCard ? "Sony card detected; CLIP is prioritized." : "No Sony card structure detected.")
            .font(.caption)
            .foregroundStyle(.secondary)
          Button("Scan Source") { vm.scan(settings: settings) }
        }
        if vm.isIngesting {
          IngestProgressView(progress: vm.progress)
          Button("Cancel") { vm.ingestService.cancel() }
        } else {
          HStack {
            Button("Start Copy") {
              Task {
                if let project = await vm.start(settings: settings) {
                  dismiss()
                  openProject(project)
                }
              }
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.videos.isEmpty || vm.destinationURL == nil)
            Button("Cancel") { dismiss() }
          }
        }
        if let canceled = vm.canceledSummary {
          GroupBox("Ingest canceled") {
            Text(canceled)
            HStack {
              Button("Open partial library") {}
              Button("Resume ingest") { Task { _ = await vm.start(settings: settings) } }
              Button("Reveal project folder") { vm.revealDestination() }
            }
          }
        }
        if let error = vm.error { Text(error).foregroundStyle(.red) }
      }
      .padding(24)
    }
  }
}
