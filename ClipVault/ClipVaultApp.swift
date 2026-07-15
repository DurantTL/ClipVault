import AppKit
import SwiftUI

/// Tracks whether any text control is being edited so bare-key menu shortcuts
/// (space, 0–5, arrows, escape) can be disabled while the user is typing.
/// Menu key equivalents fire before the responder chain, so guarding inside the
/// menu action would still swallow the keystroke; disabling the menu item lets
/// the event reach the focused text field instead.
final class TextEditingMonitor: ObservableObject {
  @Published private(set) var isEditingText = false

  private var observers: [any NSObjectProtocol] = []

  init() {
    let center = NotificationCenter.default
    let begin: [Notification.Name] = [
      NSControl.textDidBeginEditingNotification, NSText.didBeginEditingNotification,
    ]
    let end: [Notification.Name] = [
      NSControl.textDidEndEditingNotification, NSText.didEndEditingNotification,
    ]
    for name in begin {
      observers.append(
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          self?.isEditingText = true
        })
    }
    for name in end {
      observers.append(
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          self?.isEditingText = self?.textViewIsFirstResponder ?? false
        })
    }
  }

  deinit {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }

  private var textViewIsFirstResponder: Bool {
    NSApp.keyWindow?.firstResponder is NSTextView
  }
}

@main
struct ClipVaultApp: App {
  @StateObject private var settings = AppSettings()
  @StateObject private var textEditingMonitor = TextEditingMonitor()
  @AppStorage("appAppearance") private var appAppearanceRaw = AppAppearance.system.rawValue
  @AppStorage("appAccentColor") private var appAccentColorRaw = AppAccentColor.system.rawValue

  private var appAppearance: AppAppearance {
    AppAppearance(rawValue: appAppearanceRaw) ?? .system
  }

  private var appAccentColor: AppAccentColor {
    AppAccentColor(rawValue: appAccentColorRaw) ?? .system
  }

  var body: some Scene {
    WindowGroup(AppBrand.appName) {
      RootView()
        .environmentObject(settings)
        .preferredColorScheme(appAppearance.colorScheme)
        .tint(appAccentColor.color)
    }
    .commands {
      CommandMenu("Clip") {
        Group {
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
        }
        .disabled(textEditingMonitor.isEditingText)
        Button("Reveal in Finder") { NotificationCenter.default.post(name: .clipReveal, object: nil) }
          .keyboardShortcut("r")
        Button("Close Preview") { NotificationCenter.default.post(name: .clipClosePreview, object: nil) }
          .keyboardShortcut(.escape, modifiers: [])
          .disabled(textEditingMonitor.isEditingText)
      }
      CommandGroup(after: .help) {
        Divider()
        Button("Welcome to \(AppBrand.appName)") { NotificationCenter.default.post(name: .showOnboarding, object: nil) }
        Button("Keyboard Shortcuts") { NotificationCenter.default.post(name: .showKeyboardShortcuts, object: nil) }
        Divider()
        Button("Save Diagnostics Report…") { DiagnosticsReportService().saveViaPanel() }
      }
    }

    Settings {
      SettingsView()
        .environmentObject(settings)
        .preferredColorScheme(appAppearance.colorScheme)
        .tint(appAccentColor.color)
    }
    .defaultSize(width: 900, height: 700)
    .windowResizability(.contentMinSize)
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
  static let showOnboarding = Notification.Name("showOnboarding")
  static let showKeyboardShortcuts = Notification.Name("showKeyboardShortcuts")
}
