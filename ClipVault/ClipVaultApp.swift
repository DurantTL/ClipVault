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
        Button("Favorite / Best Keep (5★)") { NotificationCenter.default.post(name: .clipKeep, object: nil) }
          .keyboardShortcut("5", modifiers: [])
        Button("Keep (4★)") { NotificationCenter.default.post(name: .clipRating4, object: nil) }
          .keyboardShortcut("4", modifiers: [])
        Button("Maybe (3★)") { NotificationCenter.default.post(name: .clipMaybe, object: nil) }
          .keyboardShortcut("3", modifiers: [])
        Button("Maybe – Low (2★)") { NotificationCenter.default.post(name: .clipRating2, object: nil) }
          .keyboardShortcut("2", modifiers: [])
        Button("Reject (1★)") { NotificationCenter.default.post(name: .clipReject, object: nil) }
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
  static let clipRating2 = Notification.Name("clipRating2")
  static let clipRating4 = Notification.Name("clipRating4")
  static let clipReveal = Notification.Name("clipReveal")
  static let clipPreview = Notification.Name("clipPreview")
  static let clipNext = Notification.Name("clipNext")
  static let clipPrevious = Notification.Name("clipPrevious")
  static let clipClosePreview = Notification.Name("clipClosePreview")
}
