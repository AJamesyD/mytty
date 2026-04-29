import AppKit

extension NSScreen {
  // CoreGraphics display ID for this screen. Used by libghostty for
  // CVDisplayLink vsync on multi-monitor setups.
  // Ref: vendor/ghostty/macos/Sources/Helpers/Extensions/NSScreen+Extension.swift
  var displayID: UInt32? {
    deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32
  }
}
