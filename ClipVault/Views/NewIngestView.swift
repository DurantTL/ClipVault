import AppKit
import SwiftUI

struct NewIngestView: View {
  @EnvironmentObject var settings: AppSettings
  @Environment(\.dismiss) var dismiss
  @StateObject var vm = NewIngestViewModel()
  let openProject: (ClipVaultProject) -> Void
  var onClose: (() -> Void)? = nil

  var body: some View {
    HStack(spacing: 0) {
      sourceSidebar
      Divider()
      sessionReview
      Divider()
      ingestPanel
    }
    .frame(minWidth: 1150, idealWidth: 1250, minHeight: 740, idealHeight: 820)
    .background(Color(nsColor: .windowBackgroundColor))
    .onAppear { vm.refreshSources() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      vm.refreshSources()
    }
  }

  private var sourceSidebar: some View {
    VStack(alignment: .leading, spacing: 12) {
      AppHeaderView(subtitle: "Session-based ingest", logoSize: 48)
      HStack {
        Text("Sources")
          .font(.title3.bold())
        Spacer()
        Button("Refresh", systemImage: "arrow.clockwise") { vm.refreshSources() }
          .labelStyle(.iconOnly)
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          sourceSection("Detected Cards", kinds: [.removableCard])
          sourceSection("External Drives", kinds: [.externalDrive, .internalDrive])
          sourceSection("Cloud / Synced Drives", kinds: [.cloudDrive])
          sourceSection("Network Volumes", kinds: [.networkVolume])
          sourceSection("Other Folders", kinds: [.folder, .unknown], includeManual: true)
        }
      }
      Button("Add Source", systemImage: "plus") { vm.chooseSource(settings: settings) }
        .buttonStyle(.borderedProminent)
      Text(vm.sourceURL?.path ?? "No source selected")
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(3)
      Label(vm.detectedCardType.summary, systemImage: vm.detectedCardType == .generic ? "folder" : "checkmark.seal.fill")
        .font(.caption)
        .foregroundStyle(vm.detectedCardType == .generic ? Color.secondary : Color.green)
    }
    .padding(18)
    .frame(width: 230)
  }

  private func sourceSection(_ title: String, kinds: [SourceVolumeKind], includeManual: Bool = false) -> some View {
    let options = vm.sourceOptions.filter { kinds.contains($0.volumeKind) } + (includeManual ? vm.recentManualSources : [])
    return VStack(alignment: .leading, spacing: 7) {
      Text(title)
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
      if options.isEmpty {
        Text(title == "Detected Cards" ? "No cards detected" : "None mounted")
          .font(.caption)
          .foregroundStyle(.tertiary)
          .padding(.vertical, 2)
      } else {
        ForEach(options) { option in
          SourceVolumeCard(
            option: option,
            isSelected: vm.selectedSourceID == option.id,
            onSelect: { vm.selectDetectedSource(option, settings: settings) }
          )
        }
      }
    }
  }

  private var sessionReview: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 10) {
        Text("Detected Sessions")
          .font(.title2.bold())
          .lineLimit(1)
        Text("Grouped by recording day and 90-minute gaps before copying starts.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(2)
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            Button("Select All") { vm.selectAllSessions() }
            Button("Clear Selection") { vm.clearSessionSelection() }
            Button("Select Today") { vm.selectTodaySessions() }
            Button("Select New Only") { vm.selectNewOnlySessions() }
            DatePicker("Select by Date", selection: $vm.selectDate, displayedComponents: .date)
              .labelsHidden()
            Button("Select by Date") { vm.selectSessions(on: vm.selectDate) }
            Button("Reload") { vm.scan(settings: settings) }
          }
          .padding(.bottom, 2)
        }
      }
      ScrollView {
        LazyVStack(spacing: 12) {
          ForEach(vm.sessions) { session in
            SessionCard(
              session: session,
              selected: Binding(get: {
                vm.sessions.first(where: { $0.id == session.id })?.selected ?? false
              }, set: { vm.setSession(session, selected: $0) }),
              onToggleSession: { vm.toggleSession(session) },
              onSetClip: { clip, selected in vm.setClip(clip, in: session, selected: selected) },
              onQueueClipThumbnail: { clip in vm.queuePreviewThumbnail(for: clip) },
              onQueueSessionThumbnails: { session in vm.queuePreviewThumbnails(for: session, limit: 24) }
            )
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
    .frame(minWidth: 600, maxWidth: .infinity)
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
        Picker("Grouping", selection: $vm.groupingMode) {
          ForEach(IngestGroupingMode.allCases) { Text($0.rawValue).tag($0) }
        }
        Picker("Time Gap", selection: $vm.timeGap) {
          ForEach(IngestTimeGap.allCases) { Text($0.label).tag($0) }
        }
        .disabled(vm.groupingMode != .dateAndGap)
        Picker("Already Imported", selection: $vm.alreadyImportedMode) {
          ForEach(AlreadyImportedMode.allCases) { Text($0.rawValue).tag($0) }
        }
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
        InfoRow("Sessions", "\(vm.selectedSessions.count) of \(vm.sessions.count)")
        InfoRow("Total Selected Videos", "\(vm.selectedClipCount)")
        InfoRow("Total Selected Size", FileSizeFormatterUtil.string(vm.selectedTotalSize))
        statusArea
        Spacer(minLength: 8)
        Button("Start Ingest") {
          Task {
            if let project = await vm.start(settings: settings) {
              openProject(project)
              closeIngestWindow()
            }
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(vm.selectedVideos.isEmpty || vm.projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.destinationURL == nil)
        Button("Cancel") {
          vm.cancelPreviewThumbnailWork()
          if vm.isIngesting { vm.ingestService.cancel() }
          closeIngestWindow()
        }
      }
      .padding(20)
    }
    .frame(width: 360)
  }

  private func closeIngestWindow() {
    if let onClose {
      onClose()
    } else {
      dismiss()
    }
  }

  @ViewBuilder private var statusArea: some View {
    let message = vm.statusMessage
    if !message.isEmpty {
      Label(message, systemImage: vm.error == nil ? "info.circle" : "exclamationmark.triangle.fill")
        .font(.caption)
        .foregroundStyle(vm.error == nil ? Color.secondary : Color.red)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((vm.error == nil ? Color.secondary : Color.red).opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }
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
    if let summary = vm.canceledSummary {
      Text(summary).foregroundStyle(.orange)
    }
  }
}

struct SessionCard: View {
  let session: IngestSession
  @Binding var selected: Bool
  let onToggleSession: () -> Void
  let onSetClip: (ScannedVideo, Bool) -> Void
  let onQueueClipThumbnail: (ScannedVideo) -> Void
  let onQueueSessionThumbnails: (IngestSession) -> Void
  @State private var expanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 14) {
        Toggle("", isOn: $selected)
          .labelsHidden()
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text(session.title)
              .font(.headline)
            badge(session.cameraType, color: .secondary)
            if selected && !session.isPartiallySelected { badge("Selected", color: .accentColor) }
            if session.isPartiallySelected { badge("Partial selection", color: .orange) }
          }
          Text("\(session.selectedClipCount) of \(session.clips.count) videos selected • \(FileSizeFormatterUtil.string(session.selectedSize)) • \(timeRange)")
            .font(.caption)
            .foregroundStyle(.secondary)
          thumbnailStrip
        }
        Spacer()
        Button { expanded.toggle() } label: {
          Label(expanded ? "Collapse" : "Expand", systemImage: expanded ? "chevron.up" : "chevron.down")
        }
        .buttonStyle(.borderless)
      }
      .contentShape(Rectangle())
      .onTapGesture { onToggleSession() }

      if expanded {
        Divider()
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 8)], alignment: .leading, spacing: 8) {
          ForEach(session.clips) { clip in
            ClipSelectionRow(
              clip: clip,
              isSelected: Binding(get: { clip.selected }, set: { onSetClip(clip, $0) }),
              onQueueThumbnail: { onQueueClipThumbnail(clip) }
            )
          }
        }
      }
    }
    .padding(14)
    .background(selected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
    .overlay(
      RoundedRectangle(cornerRadius: 16)
        .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.16), lineWidth: selected ? 2 : 1)
    )
    .onAppear { onQueueSessionThumbnails(session) }
    .onChange(of: expanded) { isExpanded in
      if isExpanded { onQueueSessionThumbnails(session) }
    }
  }

  private var thumbnailStrip: some View {
    HStack(spacing: 6) {
      ForEach(Array(session.clips.prefix(7).enumerated()), id: \.element.id) { _, clip in
        IngestPreviewThumbnailView(clip: clip, width: 54, height: 38)
          .overlay(alignment: .topTrailing) {
            if clip.selected {
              Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .background(.thinMaterial, in: Circle())
                .padding(3)
            }
          }
          .onAppear { onQueueClipThumbnail(clip) }
      }
      if session.clips.count > 7 {
        Text("+\(session.clips.count - 7)")
          .font(.caption.bold())
          .frame(width: 54, height: 38)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
      }
    }
  }

  private func badge(_ text: String, color: Color) -> some View {
    Text(text)
      .font(.caption.bold())
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(color.opacity(0.14), in: Capsule())
      .foregroundStyle(color)
  }

  private var timeRange: String {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    return "\(formatter.string(from: session.startTime))–\(formatter.string(from: session.endTime))"
  }
}

struct ClipSelectionRow: View {
  let clip: ScannedVideo
  @Binding var isSelected: Bool
  let onQueueThumbnail: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      IngestPreviewThumbnailView(clip: clip, width: 54, height: 38)
        .onAppear(perform: onQueueThumbnail)
      Toggle(isOn: $isSelected) {
        VStack(alignment: .leading, spacing: 3) {
          Text(clip.filename)
          .font(.caption.bold())
          .lineLimit(1)
          Text(FileSizeFormatterUtil.string(clip.fileSize))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
      .toggleStyle(.checkbox)
    }
    .padding(8)
    .background(isSelected ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
  }
}

struct IngestPreviewThumbnailView: View {
  let clip: ScannedVideo
  let width: CGFloat
  let height: CGFloat

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8)
        .fill(.quaternary)
      if let image = previewImage {
        Image(nsImage: image)
          .resizable()
          .scaledToFill()
          .frame(width: width, height: height)
          .clipped()
      } else if clip.previewThumbnailStatus == .generating {
        Text("Generating…")
          .font(.system(size: 8, weight: .medium))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(3)
      } else {
        Image(systemName: "film")
          .foregroundStyle(Color.secondary)
      }
    }
    .frame(width: width, height: height)
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  private var previewImage: NSImage? {
    guard let path = clip.previewThumbnailPath, FileManager.default.fileExists(atPath: path) else {
      return nil
    }
    return NSImage(contentsOfFile: path)
  }
}


struct SourceVolumeCard: View {
  let option: SourceVolumeOption
  let isSelected: Bool
  let onSelect: () -> Void

  var body: some View {
    Button(action: onSelect) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: option.iconName)
          .font(.title3)
          .frame(width: 24)
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text(option.name)
              .font(.subheadline.weight(.semibold))
              .lineLimit(1)
            if !option.isAvailable {
              Text("Disconnected")
                .font(.caption2.bold())
                .foregroundStyle(.red)
            }
          }
          Text(option.capacitySummary)
            .font(.caption)
            .foregroundStyle(.secondary)
          HStack(spacing: 5) {
            Text(option.volumeKind.rawValue)
              .font(.caption2.bold())
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(Color.secondary.opacity(0.12), in: Capsule())
            if option.structureBadge != .noVideosFound {
              Text(option.structureBadge.rawValue)
                .font(.caption2.bold())
                .foregroundStyle(option.structureBadge == .sony || option.structureBadge == .canonDCF ? .green : .secondary)
            }
          }
        }
        Spacer(minLength: 0)
      }
      .padding(9)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(isSelected ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.12)))
    }
    .buttonStyle(.plain)
    .disabled(!option.isAvailable)
  }
}
