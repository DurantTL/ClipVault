import SwiftUI

struct NewIngestView: View {
  @EnvironmentObject var settings: AppSettings
  @Environment(\.dismiss) var dismiss
  @StateObject var vm = NewIngestViewModel()
  let openProject: (ClipVaultProject) -> Void

  var body: some View {
    HStack(spacing: 0) {
      sourceSidebar
      Divider()
      sessionReview
      Divider()
      ingestPanel
    }
    .frame(minWidth: 1120, minHeight: 720)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var sourceSidebar: some View {
    VStack(alignment: .leading, spacing: 18) {
      AppHeaderView(subtitle: "Session-based ingest", logoSize: 48)
      volumeGroup("Removable Volumes", icon: "sdcard")
      volumeGroup("External Volumes", icon: "externaldrive")
      volumeGroup("Network Volumes", icon: "network")
      volumeGroup("Other Volumes", icon: "folder")
      Button("Add Source", systemImage: "plus") { vm.chooseSource(settings: settings) }
        .buttonStyle(.borderedProminent)
      Text(vm.sourceURL?.path ?? "No source selected")
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(3)
      Label(vm.detectedCardType.summary, systemImage: vm.detectedCardType == .generic ? "folder" : "checkmark.seal.fill")
        .font(.caption)
        .foregroundStyle(vm.detectedCardType == .generic ? .secondary : .green)
      Spacer()
    }
    .padding(20)
    .frame(width: 250)
  }

  private func volumeGroup(_ title: String, icon: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(title, systemImage: icon)
        .font(.headline)
      Text("Choose a mounted folder or card source.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var sessionReview: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading) {
          Text("Detected Sessions")
            .font(.title2.bold())
          Text("Grouped by recording day and 90-minute gaps before copying starts.")
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button("Select All") { vm.selectAllSessions() }
        Button("Clear Selection") { vm.clearSessionSelection() }
        Button("Select Today") { vm.selectTodaySessions() }
        Button("Select New Only") { vm.selectNewOnlySessions() }
        Button("Reload") { vm.scan(settings: settings) }
      }
      ScrollView {
        LazyVStack(spacing: 12) {
          ForEach(vm.sessions) { session in
            SessionCard(session: session, selected: Binding(get: {
              vm.sessions.first(where: { $0.id == session.id })?.selected ?? false
            }, set: { vm.setSession(session, selected: $0) }))
          }
          if vm.sessions.isEmpty {
            ContentUnavailableView("No sessions scanned", systemImage: "film.stack", description: Text("Add a source or reload the selected source."))
              .padding(40)
          }
        }
      }
      progressSection
    }
    .padding(22)
    .frame(minWidth: 560)
  }

  private var ingestPanel: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text("Ingest Setup")
          .font(.title3.bold())
        TextField("Project Name", text: $vm.projectName)
          .textFieldStyle(.roundedBorder)
        TextField("Shoot/Subfolder Name (optional)", text: $vm.shootName)
          .textFieldStyle(.roundedBorder)
        Button("Change Destination", systemImage: "folder.badge.plus") { vm.chooseDestination() }
        Text(vm.destinationURL?.path ?? "No destination selected")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(3)
        Picker("Verification Mode", selection: $settings.verificationModeRaw) {
          ForEach(VerificationMode.allCases) { Text($0.label).tag($0.rawValue) }
        }
        Picker("Thumbnail Quality", selection: $settings.thumbnailQualityRaw) {
          ForEach(ThumbnailQuality.allCases) { Text($0.rawValue.capitalized).tag($0.rawValue) }
        }
        Toggle("Rename files", isOn: $settings.renameFilesDuringIngest)
        Text("When enabled: [Project Name]-[YYYY][MM][DD]-[Sequence]. Original filenames remain in project metadata.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Toggle("Generate thumbnails during ingest", isOn: $settings.generateThumbnailsDuringIngest)
        Toggle("Run local analysis after ingest", isOn: $settings.runAnalysisAfterIngest)
        Toggle("Generate contact sheets after ingest", isOn: $settings.generateContactSheetsAfterIngest)
        Text("ClipVault can use ingest downtime to prepare previews and local analysis after files are safely copied.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Picker("Backup Transfer Mode", selection: $settings.backupTransferMode) {
          Text("Primary only").tag("Primary only")
          Text("Primary + Backup 1").tag("Primary + Backup 1")
          Text("Primary + Backup 1 + Backup 2").tag("Primary + Backup 1 + Backup 2")
        }
        Button("Choose Backup 1") { vm.chooseBackup1(settings: settings) }
        Button("Choose Backup 2") { vm.chooseBackup2(settings: settings) }
        Divider()
        InfoRow("Total Selected Videos", "\(vm.selectedVideos.count)")
        InfoRow("Total Selected Size", FileSizeFormatterUtil.string(vm.selectedTotalSize))
        Button("Start Ingest") {
          Task {
            if let project = await vm.start(settings: settings) {
              dismiss()
              openProject(project)
            }
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(vm.selectedVideos.isEmpty || vm.projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.destinationURL == nil)
        Button("Cancel") { dismiss() }
      }
      .padding(20)
    }
    .frame(width: 310)
  }

  @ViewBuilder private var progressSection: some View {
    if vm.isIngesting {
      CardContainer {
        VStack(alignment: .leading, spacing: 10) {
          Label("Copy Progress", systemImage: "arrow.down.doc")
            .font(.headline)
          IngestProgressView(progress: vm.progress)
          HStack {
            Button("Pause") { vm.ingestService.pause() }
            Button("Resume") { vm.ingestService.resume() }
            Button("Cancel") { vm.ingestService.cancel() }
          }
        }
      }
    }
    if let error = vm.error {
      Text(error).foregroundStyle(.red)
    }
  }
}

struct SessionCard: View {
  let session: IngestSession
  @Binding var selected: Bool

  var body: some View {
    CardContainer {
      HStack(alignment: .top, spacing: 14) {
        Toggle("", isOn: $selected)
          .labelsHidden()
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text(session.title)
              .font(.headline)
            Text(session.cameraType)
              .font(.caption.bold())
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(.quaternary, in: Capsule())
          }
          Text("\(session.clips.count) videos • \(FileSizeFormatterUtil.string(session.totalSize)) • \(timeRange)")
            .font(.caption)
            .foregroundStyle(.secondary)
          HStack(spacing: 6) {
            ForEach(Array(session.clips.prefix(7).enumerated()), id: \.element.id) { _, clip in
              ZStack {
                RoundedRectangle(cornerRadius: 8)
                  .fill(.quaternary)
                  .frame(width: 54, height: 38)
                Image(systemName: "film")
                  .foregroundStyle(.secondary)
                Text(clip.filename)
                  .font(.system(size: 6))
                  .lineLimit(1)
                  .frame(width: 46)
                  .offset(y: 15)
              }
            }
            if session.clips.count > 7 {
              Text("+\(session.clips.count - 7)")
                .font(.caption.bold())
                .frame(width: 54, height: 38)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
          }
        }
        Spacer()
      }
    }
  }

  private var timeRange: String {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    return "\(formatter.string(from: session.startTime))–\(formatter.string(from: session.endTime))"
  }
}
