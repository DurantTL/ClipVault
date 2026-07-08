import SwiftUI

@main
struct ClipVaultApp: App {
  @StateObject private var settings = AppSettings()

  var body: some Scene {
    WindowGroup("ClipVault") {
      RootView()
        .environmentObject(settings)
    }
    .commands {
      CommandMenu("Clip") {
        Button("Keep") {
          NotificationCenter.default.post(name: .clipKeep, object: nil)
        }
        .keyboardShortcut("1")

        Button("Maybe") {
          NotificationCenter.default.post(name: .clipMaybe, object: nil)
        }
        .keyboardShortcut("2")

        Button("Reject") {
          NotificationCenter.default.post(name: .clipReject, object: nil)
        }
        .keyboardShortcut("3")

        Button("Reveal in Finder") {
          NotificationCenter.default.post(name: .clipReveal, object: nil)
        }
        .keyboardShortcut("r")
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
  static let clipReveal = Notification.Name("clipReveal")
}
