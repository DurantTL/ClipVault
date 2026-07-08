import SwiftUI

struct SidebarView: View {
  @ObservedObject var vm: LibraryViewModel
  @Binding var newFolder: String
  @State private var renameFolderName = ""

  var body: some View {
    List(selection: $vm.filter) {
      Section {
        Label("Library", systemImage: "rectangle.stack")
          .tag("All Clips")
      }

      Section("Smart Folders") {
        ForEach(vm.smartFolders, id: \.self) { folder in
          Label {
            HStack {
              Text(folder)
              Spacer()
              Text("\(count(for: folder))")
                .foregroundStyle(.secondary)
            }
          } icon: {
            Image(systemName: icon(for: folder))
          }
          .tag(folder)
        }
      }

      Section("Custom Folders") {
        ForEach(vm.project.customFolders, id: \.self) { folder in
          Label {
            HStack {
              Text(folder)
              Spacer()
              Text("\(count(for: folder))")
                .foregroundStyle(.secondary)
            }
          } icon: {
            Image(systemName: "folder")
          }
          .tag(folder)
          .dropDestination(for: Clip.self) { clips, _ in
            vm.selectedClipIDs = Set(clips.map(\.id))
            vm.selectedClipID = clips.first?.id
            vm.moveSelected(to: folder)
            return true
          }
          .contextMenu {
            Button("Rename Folder") {
              renameFolderName = folder
              vm.renameFolder(folder, to: renameFolderName)
            }
            Button("Delete Folder Assignment", role: .destructive) {
              vm.deleteFolder(folder)
            }
          }
        }

        HStack {
          TextField("New folder", text: $newFolder)
          Button("Add") {
            vm.addFolder(newFolder)
            newFolder = ""
          }
        }
      }

      Section("Production Tags") {
        ForEach(vm.productionTags, id: \.self) { tag in
          Label(tag, systemImage: "tag")
            .tag(tag)
        }
      }
    }
    .navigationTitle(vm.project.name)
    .listStyle(.sidebar)
  }

  private func count(for folder: String) -> Int {
    vm.project.clips.filter { clip in
      switch folder {
      case "All Clips": return true
      case "Unrated": return clip.cullStatus == .unrated
      case "Keep": return clip.cullStatus == .keep
      case "Maybe": return clip.cullStatus == .maybe
      case "Reject": return clip.cullStatus == .reject
      default:
        return clip.assignedFolder == folder || clip.automaticTags.contains(folder) || clip.productionTags.contains(folder)
      }
    }.count
  }

  private func icon(for folder: String) -> String {
    switch folder {
    case "Keep": return "checkmark.circle"
    case "Maybe": return "questionmark.circle"
    case "Reject": return "xmark.circle"
    case "Failed Preview", "Failed Verification": return "exclamationmark.triangle"
    case "4K", "60p": return "4k.tv"
    case "Has Audio", "No Audio": return "waveform"
    default: return "line.3.horizontal.decrease.circle"
    }
  }
}
