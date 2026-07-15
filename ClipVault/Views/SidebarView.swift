import SwiftUI

struct SidebarView: View {
  @ObservedObject var vm: LibraryViewModel
  @Binding var newFolder: String
  @State private var renameFolderName = ""
  @State private var renameTargetFolder: String?

  var body: some View {
    List(selection: $vm.filter) {
      Section {
        Label("Library", systemImage: "rectangle.stack")
          .tag("All Clips")
      }

      Section("Workflow") {
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
              renameTargetFolder = folder
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
    .alert(
      "Rename Folder",
      isPresented: Binding(
        get: { renameTargetFolder != nil },
        set: { if !$0 { renameTargetFolder = nil } }
      )
    ) {
      TextField("Folder name", text: $renameFolderName)
      Button("Rename") {
        if let target = renameTargetFolder {
          vm.renameFolder(target, to: renameFolderName)
        }
        renameTargetFolder = nil
        renameFolderName = ""
      }
      Button("Cancel", role: .cancel) {
        renameTargetFolder = nil
        renameFolderName = ""
      }
    } message: {
      Text("Renaming updates the folder assignment on every clip in the folder.")
    }
  }

  private func count(for folder: String) -> Int {
    vm.clipCount(for: folder)
  }

  private func icon(for folder: String) -> String {
    switch folder {
    case "Keep": return "checkmark.circle"
    case "Maybe": return "questionmark.circle"
    case "Reject": return "xmark.circle"
    case "Needs Review": return "exclamationmark.triangle"
    default: return "line.3.horizontal.decrease.circle"
    }
  }
}
