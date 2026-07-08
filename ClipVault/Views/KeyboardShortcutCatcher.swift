import AppKit
import SwiftUI

struct KeyboardShortcutCatcher: NSViewRepresentable {
  let handle: (NSEvent) -> Bool

  func makeNSView(context: Context) -> KeyCatcherView {
    let view = KeyCatcherView()
    view.handle = handle
    DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
    return view
  }

  func updateNSView(_ nsView: KeyCatcherView, context: Context) {
    nsView.handle = handle
    DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
  }
}

final class KeyCatcherView: NSView {
  var handle: ((NSEvent) -> Bool)?
  override var acceptsFirstResponder: Bool { true }

  override func keyDown(with event: NSEvent) {
    if handle?(event) == true { return }
    super.keyDown(with: event)
  }
}
