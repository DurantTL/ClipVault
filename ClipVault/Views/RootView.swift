import SwiftUI
struct RootView: View { @State private var project: ClipVaultProject?; var body: some View { Group { if let p = project { LibraryView(viewModel: LibraryViewModel(project: p)) } else { HomeView(openProject: { project = $0 }) } }.frame(minWidth: 1100, minHeight: 720) } }
