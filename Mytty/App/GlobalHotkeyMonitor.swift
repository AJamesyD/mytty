import AppKit
import CoreGraphics

// Sendable: all mutation happens on the main thread (enable/disable called from @MainActor,
// timer and event tap attached to the main run loop).
class GlobalHotkeyMonitor: @unchecked Sendable {
  private var eventTap: CFMachPort?
  private var enableTimer: Timer?

  deinit {
    disable()
  }

  func enable() {
    if eventTap != nil { return }
    enableTimer?.invalidate()
    if tryEnable() {
      return
    }
    enableTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
      _ = self.tryEnable()
    }
  }

  func disable() {
    enableTimer?.invalidate()
    enableTimer = nil
    if let eventTap {
      CFMachPortInvalidate(eventTap)
      self.eventTap = nil
    }
  }

  private func tryEnable() -> Bool {
    let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventMask,
        callback: globalHotkeyCallback,
        userInfo: nil
      )
    else { return false }

    eventTap = tap
    enableTimer?.invalidate()
    enableTimer = nil

    CFRunLoopAddSource(
      CFRunLoopGetMain(),
      CFMachPortCreateRunLoopSource(nil, tap, 0),
      .commonModes
    )
    return true
  }
}

// The tap runs on CFRunLoopGetMain, so this callback executes on the main thread.
private func globalHotkeyCallback(
  proxy: CGEventTapProxy,
  type: CGEventType,
  cgEvent: CGEvent,
  userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  let result = Unmanaged.passUnretained(cgEvent)
  guard type == .keyDown else { return result }

  let keyCode = cgEvent.getIntegerValueField(.keyboardEventKeycode)
  let flags = cgEvent.flags
  // Keycode 50 = backtick on US keyboard layout
  guard keyCode == 50,
    flags.contains(.maskControl),
    !flags.contains(.maskShift),
    !flags.contains(.maskAlternate),
    !flags.contains(.maskCommand)
  else { return result }

  MainActor.assumeIsolated {
    NotificationCenter.default.post(name: .myttyDropdownHotkeyPressed, object: nil)
  }
  return nil
}
