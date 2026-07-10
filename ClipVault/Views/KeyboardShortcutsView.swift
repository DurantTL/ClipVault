import SwiftUI

/// Static cheat sheet for the library and preview shortcuts, opened from
/// Help → Keyboard Shortcuts.
struct KeyboardShortcutsView: View {
  @Environment(\.dismiss) private var dismiss

  private struct Shortcut: Identifiable {
    let keys: String
    let action: String
    var id: String { keys + action }
  }

  private struct Section: Identifiable {
    let title: String
    let shortcuts: [Shortcut]
    var id: String { title }
  }

  private let sections: [Section] = [
    Section(title: "Rating and Culling", shortcuts: [
      Shortcut(keys: "5", action: "Favorite / Best Keep (5★)"),
      Shortcut(keys: "4", action: "Keep (4★)"),
      Shortcut(keys: "3", action: "Maybe (3★)"),
      Shortcut(keys: "2", action: "Maybe – Low (2★)"),
      Shortcut(keys: "1", action: "Reject (1★)"),
      Shortcut(keys: "0", action: "Clear rating / Unrated")
    ]),
    Section(title: "Navigation and Preview", shortcuts: [
      Shortcut(keys: "Space", action: "Preview selected clip, or play/pause in preview"),
      Shortcut(keys: "→ / ←", action: "Select next or previous clip"),
      Shortcut(keys: "Esc", action: "Close preview, or clear the multi-selection")
    ]),
    Section(title: "Selection", shortcuts: [
      Shortcut(keys: "⌘ Click", action: "Add or remove a clip from the selection"),
      Shortcut(keys: "⇧ Click", action: "Select a range of visible clips"),
      Shortcut(keys: "⌘ A", action: "Select all visible clips")
    ]),
    Section(title: "Actions", shortcuts: [
      Shortcut(keys: "⌘ R", action: "Reveal selected clip(s) in Finder")
    ])
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Keyboard Shortcuts")
        .font(.title2.bold())
        .padding(.bottom, 16)

      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          ForEach(sections) { section in
            VStack(alignment: .leading, spacing: 6) {
              Text(section.title)
                .font(.headline)
              ForEach(section.shortcuts) { shortcut in
                HStack(alignment: .firstTextBaseline) {
                  Text(shortcut.keys)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .frame(width: 90, alignment: .leading)
                  Text(shortcut.action)
                    .foregroundStyle(.secondary)
                  Spacer(minLength: 0)
                }
              }
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      HStack {
        Spacer()
        Button("Done") { dismiss() }
          .keyboardShortcut(.defaultAction)
      }
      .padding(.top, 16)
    }
    .padding(28)
    .frame(width: 480, height: 520)
  }
}
