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
        AppHeaderView(subtitle: "Guided, verified media ingest", logoSize: 56)
        sourceSection
        destinationSection
        optionsSection
        scanSection
        progressSection
        canceledSection
        if let error = vm.error { Text(error).foregroundStyle(.red) }
      }
      .padding(24)
    }
  }

  private var sourceSection: some View {
    CardContainer {
      VStack(alignment: .leading, spacing: 10) {
        Label("Source", systemImage: "externaldrive")
          .font(.headline)
        HStack {
          Button("Choose Source") { vm.chooseSource(settings: settings) }
          Text(vm.sourceURL?.path ?? "No source selected").lineLimit(1)
        }
        Label(vm.isSonyCard ? "Sony card detected: PRIVATE/M4ROOT/CLIP" : "Generic folder", systemImage: vm.isSonyCard ? "checkmark.seal.fill" : "folder")
          .foregroundStyle(vm.isSonyCard ? .green : .secondary)
      }
    }
  }

  private var destinationSection: some View {
    CardContainer {
      VStack(alignment: .leading, spacing: 10) {
        Label("Destination", systemImage: "folder.badge.plus")
          .font(.headline)
        HStack {
          Button("Choose Destination Parent Folder") { vm.chooseDestination() }
          Text(vm.destinationURL?.path ?? "No destination selected").lineLimit(1)
        }
        TextField("Project Folder Name", text: $vm.projectName)
          .textFieldStyle(.roundedBorder)
        TextField("Shoot/Subfolder Name (optional)", text: $vm.shootName)
          .textFieldStyle(.roundedBorder)
        Text("Final Output: \(vm.finalOutputURL?.path ?? "Choose a destination")")
          .font(.caption)
          .textSelection(.enabled)
        HStack {
          Button("Create Project Folder") { vm.createProjectFolder() }
          Button("Reveal Destination") { vm.revealDestination() }
        }
      }
    }
  }

  private var optionsSection: some View {
    CardContainer {
      VStack(alignment: .leading, spacing: 10) {
        Label("Options", systemImage: "slider.horizontal.3")
          .font(.headline)
        Picker("Folder Structure Mode", selection: $settings.preserveSourceStructure) {
          Text("Flat").tag(false)
          Text("Preserve Source Structure").tag(true)
        }
        Toggle("Include Sony proxy files", isOn: $settings.includeProxyFiles)
          .onChange(of: settings.includeProxyFiles) { vm.scan(settings: settings) }
        Picker("Verification Mode", selection: $settings.verificationModeRaw) {
          ForEach(VerificationMode.allCases) { Text($0.label).tag($0.rawValue) }
        }
        Picker("Thumbnail Quality", selection: $settings.thumbnailQualityRaw) {
          ForEach(ThumbnailQuality.allCases) { Text($0.rawValue.capitalized).tag($0.rawValue) }
        }
      }
    }
  }

  private var scanSection: some View {
    CardContainer {
      VStack(alignment: .leading, spacing: 10) {
        Label("Scan Summary", systemImage: "list.bullet.rectangle")
          .font(.headline)
        HStack {
          Text("\(vm.videos.count) videos")
          Spacer()
          Text(FileSizeFormatterUtil.string(total))
        }
        if let free = vm.destinationFreeSpace {
          Text("Estimated destination free space: \(FileSizeFormatterUtil.string(free))")
          if free < total {
            Label("Destination free space may be too low.", systemImage: "externaldrive.badge.exclamationmark")
              .foregroundStyle(.red)
          }
        }
        Text(vm.isSonyCard ? "Sony card detected; CLIP is prioritized." : "No Sony card structure detected.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text("Final copy mode: \(settings.preserveSourceStructure ? "Preserve Source Structure" : "Flat")")
          .font(.caption)
          .foregroundStyle(.secondary)
        Button("Scan Source") { vm.scan(settings: settings) }
      }
    }
  }

  @ViewBuilder private var progressSection: some View {
    if vm.isIngesting {
      CardContainer {
        VStack(alignment: .leading, spacing: 10) {
          Label("Copy Progress", systemImage: "arrow.down.doc")
            .font(.headline)
          IngestProgressView(progress: vm.progress)
          Text("Keep the SD card and destination drive connected until ingest finishes.")
            .font(.caption)
            .foregroundStyle(.secondary)
          Button("Cancel") { vm.ingestService.cancel() }
        }
      }
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
  }

  @ViewBuilder private var canceledSection: some View {
    if let canceled = vm.canceledSummary {
      CardContainer {
        VStack(alignment: .leading, spacing: 10) {
          Label("Ingest canceled", systemImage: "pause.circle")
            .font(.headline)
          Text(canceled)
          HStack {
            Button("Open Partial Library") {}
            Button("Resume Ingest") { Task { _ = await vm.start(settings: settings) } }
            Button("Retry Failed Files") { Task { _ = await vm.start(settings: settings) } }
            Button("Reveal Project Folder") { vm.revealDestination() }
          }
        }
      }
    }
  }
}
