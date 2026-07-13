import SwiftUI

struct RootView: View {
  @State private var project: ClipVaultProject?
  @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
  @State private var showOnboarding = false
  @State private var showShortcuts = false

  var body: some View {
    Group {
      if let p = project {
        LibraryView(viewModel: LibraryViewModel(project: p))
      } else {
        HomeView(openProject: { project = $0 })
      }
    }
    .frame(minWidth: 1100, minHeight: 720)
    .onAppear {
      if !hasCompletedOnboarding { showOnboarding = true }
    }
    .onReceive(NotificationCenter.default.publisher(for: .showOnboarding)) { _ in
      showOnboarding = true
    }
    .onReceive(NotificationCenter.default.publisher(for: .showKeyboardShortcuts)) { _ in
      showShortcuts = true
    }
    .sheet(isPresented: $showOnboarding) {
      OnboardingView {
        hasCompletedOnboarding = true
        showOnboarding = false
      }
    }
    .sheet(isPresented: $showShortcuts) {
      KeyboardShortcutsView()
    }
  }
}
