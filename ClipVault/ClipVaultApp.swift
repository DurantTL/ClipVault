import SwiftUI

@main
struct ClipVaultApp: App {
  @StateObject private var settings = AppSettings()

  var body: some Scene {
    WindowGroup(AppBrand.appName) {
      RootView()
        .environmentObject(settings)
    }
    .commands {
      CommandMenu("Clip") {
        Button("Preview / Play") { NotificationCenter.default.post(name: .clipPreview, object: nil) }
          .keyboardShortcut(.space, modifiers: [])
        Button("Keep") { NotificationCenter.default.post(name: .clipKeep, object: nil) }
          .keyboardShortcut("5", modifiers: [])
        Button("Maybe") { NotificationCenter.default.post(name: .clipMaybe, object: nil) }
          .keyboardShortcut("3", modifiers: [])
        Button("Reject") { NotificationCenter.default.post(name: .clipReject, object: nil) }
          .keyboardShortcut("1", modifiers: [])
        Button("Unrated") { NotificationCenter.default.post(name: .clipUnrated, object: nil) }
          .keyboardShortcut("0", modifiers: [])
        Button("Next Clip") { NotificationCenter.default.post(name: .clipNext, object: nil) }
          .keyboardShortcut(.rightArrow, modifiers: [])
        Button("Previous Clip") { NotificationCenter.default.post(name: .clipPrevious, object: nil) }
          .keyboardShortcut(.leftArrow, modifiers: [])
        Button("Reveal in Finder") { NotificationCenter.default.post(name: .clipReveal, object: nil) }
          .keyboardShortcut("r")
        Button("Close Preview") { NotificationCenter.default.post(name: .clipClosePreview, object: nil) }
          .keyboardShortcut(.escape, modifiers: [])
      }
    }

    Settings {
      SettingsView()
        .environmentObject(settings)
    }
  }
}

extension Notification.Name {
  static let clipKeep = Notification.Name("clipKeep")
  static let clipMaybe = Notification.Name("clipMaybe")
  static let clipReject = Notification.Name("clipReject")
  static let clipUnrated = Notification.Name("clipUnrated")
  static let clipReveal = Notification.Name("clipReveal")
  static let clipPreview = Notification.Name("clipPreview")
  static let clipNext = Notification.Name("clipNext")
  static let clipPrevious = Notification.Name("clipPrevious")
  static let clipClosePreview = Notification.Name("clipClosePreview")
}
