import SwiftUI

/// Bulk metadata editor for the current selection. Text fields left empty
/// leave the clips untouched; tags default to append so batch edits never
/// silently erase earlier tagging.
struct BatchMetadataView: View {
  @ObservedObject var vm: LibraryViewModel
  @Environment(\.dismiss) private var dismiss
  @State private var edit = BatchMetadataEdit()

  private let shotTypes = ["", "Wide", "Medium", "Close-Up", "Detail", "Crowd", "Speaker", "Interview", "B-Roll", "Screen/Slides", "Other"]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Batch Edit \(vm.selectionCount) Clip\(vm.selectionCount == 1 ? "" : "s")")
        .font(.title3.bold())
        .padding()
      Divider()
      Form {
        Section("Tags") {
          TextField("Tags (comma separated)", text: $edit.tagsText)
          Picker("Tag Mode", selection: $edit.tagMode) {
            ForEach(BatchMetadataEdit.TagMode.allCases) { Text($0.rawValue).tag($0) }
          }
          .pickerStyle(.segmented)
        }
        Section("Fields (empty = leave unchanged)") {
          TextField("People (comma separated, appended)", text: $edit.peopleText)
          TextField("Location", text: $edit.location)
          TextField("Scene", text: $edit.scene)
          Picker("Shot Type", selection: $edit.shotType) {
            ForEach(shotTypes, id: \.self) { value in
              Text(value.isEmpty ? "Leave unchanged" : value).tag(value)
            }
          }
          TextField("Notes (replaces existing)", text: $edit.notes)
        }
        Section("Flags") {
          flagPicker("Favorite", $edit.favorite)
          flagPicker("B-Roll", $edit.broll)
          flagPicker("Sermon", $edit.sermon)
          flagPicker("Interview", $edit.interview)
          flagPicker("Social Clip Candidate", $edit.socialClipCandidate)
        }
      }
      .formStyle(.grouped)
      Divider()
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("Apply to \(vm.selectionCount)") {
          vm.applyBatchMetadata(edit)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
        .disabled(vm.selectionCount == 0)
      }
      .padding()
    }
    .frame(width: 460, height: 560)
  }

  private func flagPicker(_ title: String, _ action: Binding<BatchMetadataEdit.FlagAction>) -> some View {
    Picker(title, selection: action) {
      ForEach(BatchMetadataEdit.FlagAction.allCases) { Text($0.rawValue).tag($0) }
    }
    .pickerStyle(.segmented)
  }
}
