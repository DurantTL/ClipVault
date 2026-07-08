import SwiftUI

struct ClipInspectorView: View {
  let clip: Clip?
  @ObservedObject var vm: LibraryViewModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        if let clip {
          Text(clip.currentFilename).font(.title2.bold())
          HStack {
            Button("Preview / Play") { vm.previewSelected() }
            Button("Reveal in Finder") { vm.reveal() }
          }
          Picker("Cull Status", selection: Binding(get: { clip.cullStatus }, set: { vm.setStatus($0) })) {
            ForEach(CullStatus.allCases) { Text($0.label).tag($0) }
          }
          metadataSections(clip)
        } else {
          Text("Select a clip")
        }
      }
      .padding()
    }
    .frame(minWidth: 300)
  }

  @ViewBuilder private func metadataSections(_ clip: Clip) -> some View {
    GroupBox("Basic") {
      InfoRow("Duration", DurationFormatterUtil.string(clip.duration))
      InfoRow("Size", FileSizeFormatterUtil.string(clip.fileSize))
      InfoRow("Resolution", "\(clip.width.map(String.init) ?? "?") × \(clip.height.map(String.init) ?? "?")")
      InfoRow("Frame Rate", clip.frameRate.map { String(format: "%.2f", $0) } ?? "?")
      InfoRow("Codec", clip.codec ?? "Unavailable")
      InfoRow("Verification", clip.verificationStatus.rawValue.capitalized)
    }

    GroupBox("Production") {
      editable("Title", \.title)
      editable("Description", \.description)
      editable("Tags", \.productionTags, placeholder: "tag, tag")
      editable("People", \.people, placeholder: "person, person")
      editable("Location", \.location)
      editable("Scene", \.scene)
      editable("Shot Type", \.shotType)
      editable("Notes", \.customNotes)
      Toggle("Favorite", isOn: bind(\.favorite))
      Toggle("B-Roll", isOn: bind(\.isBroll))
      Toggle("Sermon", isOn: bind(\.isSermon))
      Toggle("Interview", isOn: bind(\.isInterview))
      Toggle("Social Clip Candidate", isOn: bind(\.isSocialClipCandidate))
    }

    GroupBox("Automatic Tags") {
      TagCloud(tags: clip.automaticTags)
    }

    GroupBox("Paths") {
      Text("Source: \(clip.originalSourcePath)").font(.caption).textSelection(.enabled)
      Text("Destination: \(clip.currentPath)").font(.caption).textSelection(.enabled)
    }

    if let message = clip.errorMessage {
      Text(message).foregroundStyle(.red)
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
            $0[keyPath: keyPath] = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
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
      Text("No automatic tags").foregroundStyle(.secondary)
    } else {
      FlowLayout(tags: tags)
    }
  }
}

struct FlowLayout: View {
  let tags: [String]
  var body: some View {
    VStack(alignment: .leading) {
      ForEach(tags, id: \.self) { tag in
        Text(tag).font(.caption).padding(5).background(.quaternary).clipShape(Capsule())
      }
    }
  }
}
