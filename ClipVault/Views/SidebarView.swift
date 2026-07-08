import SwiftUI

struct SidebarView: View {
  @ObservedObject var vm: LibraryViewModel
  @Binding var newFolder: String

  let built = ["All Clips", "Unrated", "Keep", "Maybe", "Reject"]

  var body: some View {
    List(selection: $vm.filter) {
      Section {
        Text("Home").tag("All Clips")
      }
      Section("Library Filters") {
        ForEach(built, id: \.self) { Text($0).tag($0) }
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
      Section("Production Tags") {
        ForEach(vm.productionTags, id: \.self) { tag in
          Text(tag).tag(tag)
        }
      }
    }
    .navigationTitle(vm.project.name)
  }
}
