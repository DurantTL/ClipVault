import AppKit
import SwiftUI

struct ClipInspectorView: View {
  let clip: Clip?
  @ObservedObject var vm: LibraryViewModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        if let clip {
          CardContainer {
            VStack(alignment: .leading, spacing: 12) {
              Label("Clip Summary", systemImage: "film")
                .font(.headline)
              Text(clip.currentFilename)
                .font(.title3.bold())
                .lineLimit(2)
              HStack {
                Button("Preview / Play", systemImage: "play.fill") { vm.previewSelected() }
                  .buttonStyle(.borderedProminent)
                Button("Reveal", systemImage: "arrow.up.forward.app") { vm.reveal() }
              }
              Picker("Cull Status", selection: Binding(get: { clip.cullStatus }, set: { vm.setStatus($0) })) {
                ForEach(CullStatus.allCases) { Text($0.label).tag($0) }
              }
            }
          }
          metadataSections(clip)
        } else {
          ContentUnavailableView(
            "No clip selected",
            systemImage: "rectangle.dashed",
            description: Text("Select a clip to preview metadata, paths, and culling controls.")
          )
          .padding(24)
        }
      }
      .padding()
    }
    .frame(minWidth: 320)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  @ViewBuilder private func metadataSections(_ clip: Clip) -> some View {
    inspectorCard("Technical Metadata", systemImage: "waveform.path.ecg.rectangle") {
      InfoRow("Duration", DurationFormatterUtil.string(clip.duration))
      InfoRow("Size", FileSizeFormatterUtil.string(clip.fileSize))
      InfoRow("Resolution", "\(clip.width.map(String.init) ?? "?") × \(clip.height.map(String.init) ?? "?")")
      InfoRow("Frame Rate", clip.frameRate.map { String(format: "%.2f", $0) } ?? "?")
      InfoRow("Codec", clip.codec ?? "Unavailable")
      InfoRow("Verification", clip.verificationStatus.rawValue.capitalized)
      InfoRow("Audio", clip.hasAudio == true ? "Has Audio" : "No Audio / Unknown")
    }

    inspectorCard("Production Metadata", systemImage: "tag") {
      editable("Title", \.title)
      editable("Description", \.description)
      editable("Tags", \.productionTags, placeholder: "tag, tag")
      editable("People", \.people, placeholder: "person, person")
      editable("Location", \.location)
      editable("Scene", \.scene)
      Picker("Shot Type", selection: bind(\.shotType)) {
        ForEach(["", "Wide", "Medium", "Close-Up", "Detail", "Crowd", "Speaker", "Interview", "B-Roll", "Screen/Slides", "Other"], id: \.self) { value in
          Text(value.isEmpty ? "None" : value).tag(value)
        }
      }
      editable("Notes", \.customNotes)
      Toggle("Favorite", isOn: bind(\.favorite))
      Toggle("B-Roll", isOn: bind(\.isBroll))
      Toggle("Sermon", isOn: bind(\.isSermon))
      Toggle("Interview", isOn: bind(\.isInterview))
      Toggle("Social Clip Candidate", isOn: bind(\.isSocialClipCandidate))
    }

    inspectorCard("Automatic Tags", systemImage: "sparkles") {
      TagCloud(tags: clip.automaticTags)
    }

    inspectorCard("Paths", systemImage: "folder") {
      Text("Source: \(clip.originalSourcePath)")
        .font(.caption)
        .textSelection(.enabled)
      Text("Destination: \(clip.currentPath)")
        .font(.caption)
        .textSelection(.enabled)
      Button("Copy Destination Path") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(clip.currentPath, forType: .string)
      }
      Button("Reveal in Finder") { vm.reveal() }
    }

    if let message = clip.errorMessage {
      CardContainer {
        Label(message, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
      }
    }
  }

  private func inspectorCard<Content: View>(
    _ title: String,
    systemImage: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    CardContainer {
      VStack(alignment: .leading, spacing: 10) {
        Label(title, systemImage: systemImage)
          .font(.headline)
        content()
      }
    }
  }

  private func bind<Value>(_ keyPath: WritableKeyPath<Clip, Value>) -> Binding<Value> {
    Binding(
      get: { clip?[keyPath: keyPath] ?? vm.selectedClip![keyPath: keyPath] },
      set: { value in vm.updateSelected { $0[keyPath: keyPath] = value } }
    )
  }

  private func editable(_ title: String, _ keyPath: WritableKeyPath<Clip, String>) -> some View {
    TextField(title, text: bind(keyPath))
      .textFieldStyle(.roundedBorder)
  }

  private func editable(_ title: String, _ keyPath: WritableKeyPath<Clip, [String]>, placeholder: String) -> some View {
    TextField(
      placeholder,
      text: Binding(
        get: { (clip?[keyPath: keyPath] ?? []).joined(separator: ", ") },
        set: { value in
          vm.updateSelected {
            $0[keyPath: keyPath] = value
              .split(separator: ",")
              .map { $0.trimmingCharacters(in: .whitespaces) }
              .filter { !$0.isEmpty }
          }
        }
      )
    )
    .textFieldStyle(.roundedBorder)
  }
}

struct InfoRow: View {
  let title: String
  let value: String

  init(_ title: String, _ value: String) {
    self.title = title
    self.value = value
  }

  var body: some View {
    HStack {
      Text(title)
      Spacer()
      Text(value).foregroundStyle(.secondary)
    }
    .font(.caption)
  }
}

struct TagCloud: View {
  let tags: [String]

  var body: some View {
    if tags.isEmpty {
      Text("No automatic tags yet. Run Analyze Locally to add rule-based tags.")
        .foregroundStyle(.secondary)
    } else {
      FlowLayout(tags: tags)
    }
  }
}

struct FlowLayout: View {
  let tags: [String]

  var body: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6)], alignment: .leading, spacing: 6) {
      ForEach(tags, id: \.self) { tag in
        Text(tag)
          .font(.caption)
          .padding(.horizontal, 8)
          .padding(.vertical, 5)
          .background(.quaternary, in: Capsule())
      }
    }
  }
}
