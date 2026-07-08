import SwiftUI

struct SidebarView: View {
  @ObservedObject var vm: LibraryViewModel
  @Binding var newFolder: String

  let built = ["All Clips", "Unrated", "Keep", "Maybe", "Reject"]

  var body: some View {
    List(selection: $vm.filter) {
      Section("Library") {
        ForEach(built, id: \.self) {
          Text($0)
            .tag($0)
        }
      }

      Section("Custom Folders") {
        ForEach(vm.project.customFolders, id: \.self) { folder in
          Text(folder)
            .tag(folder)
            .dropDestination(for: Clip.self) { clips, _ in
              vm.selectedClipID = clips.first?.id
              vm.moveSelected(to: folder)
              return true
            }
        }

        HStack {
          TextField("New folder", text: $newFolder)

          Button("+") {
            vm.addFolder(newFolder)
            newFolder = ""
          }
        }
      }
    }
    .navigationTitle(vm.project.name)
  }
}
