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
        Label(vm.detectedCardType.summary, systemImage: vm.detectedCardType == .generic ? "folder" : "checkmark.seal.fill")
          .foregroundStyle(vm.detectedCardType == .generic ? .secondary : .green)
      }
    }
  }

  private var destinationSection: some View {
    CardContainer {
      VStack(alignment: .leading, spacing: 10) {
        Label("Primary Destination Parent Folder", systemImage: "folder.badge.plus")
          .font(.headline)
        Text("Destination can be a local folder, external SSD, mounted NAS, or cloud-synced folder.")
          .font(.caption)
          .foregroundStyle(.secondary)
        HStack {
          Button("Choose Primary Destination") { vm.chooseDestination() }
          Text(vm.destinationURL?.path ?? "No destination selected").lineLimit(1)
        }
        Picker("Backup Transfer Mode", selection: $settings.backupTransferMode) {
          Text("Primary only").tag("Primary only")
          Text("Primary + Backup 1").tag("Primary + Backup 1")
          Text("Primary + Backup 1 + Backup 2").tag("Primary + Backup 1 + Backup 2")
        }
        HStack {
          Button("Choose Optional Backup Destination 1") { vm.chooseBackup1(settings: settings) }
          Text(settings.backupDestination1Path.isEmpty ? "No backup 1 selected" : settings.backupDestination1Path).lineLimit(1)
        }
        HStack {
          Button("Choose Optional Backup Destination 2") { vm.chooseBackup2(settings: settings) }
          Text(settings.backupDestination2Path.isEmpty ? "No backup 2 selected" : settings.backupDestination2Path).lineLimit(1)
        }
        Text("NAS and cloud-synced folders are supported as mounted local folders. NAS disconnects or permission failures can pause or fail backup retries without failing a verified primary copy.")
          .font(.caption)
          .foregroundStyle(.orange)
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
        Text(vm.detectedCardType.summary)
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
          HStack {
            Button("Pause") { vm.ingestService.pause() }
            Button("Resume") { vm.ingestService.resume() }
            Button("Cancel") { vm.ingestService.cancel() }
          }
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
