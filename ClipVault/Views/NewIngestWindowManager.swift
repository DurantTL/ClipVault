import AppKit
import SwiftUI

@MainActor
final class NewIngestWindowManager {
  static let shared = NewIngestWindowManager()

  private weak var currentWindow: NSWindow?
  private let defaultSize = NSSize(width: 1250, height: 820)
  private let minimumSize = NSSize(width: 1150, height: 740)
  private let autosaveName = "ClipVault.NewIngestWindow"

  private init() {}

  func open(settings: AppSettings, openProject: @escaping (ClipVaultProject) -> Void) {
    if let currentWindow, currentWindow.isVisible {
      currentWindow.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    let root = NewIngestView(
      openProject: openProject,
      onClose: { NewIngestWindowManager.shared.close() }
    )
    .environmentObject(settings)

    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: defaultSize),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "New Ingest"
    window.minSize = minimumSize
    window.contentMinSize = minimumSize
    window.contentViewController = NSHostingController(rootView: root)
    window.isReleasedWhenClosed = false
    window.setFrameAutosaveName(autosaveName)

    let restored = window.setFrameUsingName(autosaveName, force: false)
    if restored {
      window.setFrame(clampedFrame(for: window.frame), display: false)
    } else {
      window.setFrame(NSRect(origin: .zero, size: defaultSize), display: false)
      window.center()
    }

    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    currentWindow = window
  }

  func close() {
    currentWindow?.close()
    currentWindow = nil
  }

  private func clampedFrame(for proposedFrame: NSRect) -> NSRect {
    let visibleFrame = bestVisibleFrame(for: proposedFrame)
    var frame = proposedFrame
    frame.size.width = min(max(frame.width, minimumSize.width), visibleFrame.width)
    frame.size.height = min(max(frame.height, minimumSize.height), visibleFrame.height)

    if frame.minX < visibleFrame.minX { frame.origin.x = visibleFrame.minX }
    if frame.maxX > visibleFrame.maxX { frame.origin.x = visibleFrame.maxX - frame.width }
    if frame.minY < visibleFrame.minY { frame.origin.y = visibleFrame.minY }
    if frame.maxY > visibleFrame.maxY { frame.origin.y = visibleFrame.maxY - frame.height }
    return frame
  }

  private func bestVisibleFrame(for frame: NSRect) -> NSRect {
    let visibleFrames = NSScreen.screens.map(\.visibleFrame)
    if let containingFrame = visibleFrames.first(where: { $0.contains(frame) }) {
      return containingFrame
    }
    if let intersectingFrame = visibleFrames.max(by: { $0.intersection(frame).area < $1.intersection(frame).area }) {
      return intersectingFrame
    }
    return NSScreen.main?.visibleFrame ?? NSRect(origin: .zero, size: defaultSize)
  }
}

private extension NSRect {
  var area: CGFloat {
    guard width > 0, height > 0 else { return 0 }
    return width * height
  }
}
