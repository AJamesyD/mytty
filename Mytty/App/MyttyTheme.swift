import SwiftUI

// Semantic color tokens for Mytty chrome and overlays.
// Background and foreground tokens derive from the Ghostty terminal theme.
// Accent colors (orange, blue, red, green) are fixed.

@MainActor
enum MyttyTheme {
  private static let bg = Color(GhosttyAppManager.shared.backgroundColor)
  private static let fg = Color(GhosttyAppManager.shared.foregroundColor)

  // Pane
  static let paneDimOverlay = bg.opacity(0.2)

  // Backdrops
  static let modalBackdrop = bg.opacity(0.3)
  static let popupBackdrop = bg.opacity(0.4)

  // Overlay HUDs (WhichKey, CopyModeHelp, etc.)
  static let overlayBackground = bg.opacity(0.85)
  static let overlayBorder = Color.orange.opacity(0.6)
  static let overlayText = fg
  static let overlayTextMuted = fg.opacity(0.8)
  static let overlayKeyBadge = fg.opacity(0.2)

  // Mode indicators
  static let modeIndicatorBackground = Color.orange.opacity(0.8)
  static let bellIndicator = Color.orange
  static let commandFailedIndicator = Color.orange

  // Search
  static let searchCurrentMatch = Color.orange.opacity(0.6)
  static let searchMatch = Color.yellow.opacity(0.3)

  // Copy mode
  static let copyModeCursor = Color.yellow.opacity(0.7)
  static let copyModeSearchBar = Color.blue.opacity(0.8)
  static let selectionHighlight = Color.blue.opacity(0.3)

  // Pane borders
  static let activePaneBorder = Color.accentColor
  static let windowModePaneBorder = Color.orange

  // Tab bar
  static let activeTabBackground = Color.accentColor.opacity(0.3)
  static let inactiveTabBackground = fg.opacity(0.05)

  // Selection
  static let selectedRowBackground = Color.accentColor.opacity(0.2)

  // Chrome
  static let sidebarDivider = fg.opacity(0.08)
  static let popupBorder = fg.opacity(0.1)
  static let popupShadow = bg.opacity(0.5)

  // Sidebar
  static let sessionAccent = Color.accentColor
  static let tabCountBadge = Color.secondary.opacity(0.6)
  static let tabCountBadgeFill = Color.secondary.opacity(0.09)

  // Bell glow (distinct from bellIndicator dot color)
  static let bellGlow = Color.red
  static let commandSuccessIndicator = Color.green.opacity(0.5)
  static let sessionManagerShadow = bg.opacity(0.3)
  static let windowModeHUD = Color.orange.opacity(0.85)
  static let copyModeKeyBadge = fg.opacity(0.1)

  // Hints mode
  static let hintsBackdrop = bg.opacity(0.4)
  static let hintLabelBackground = Color.orange
  static let hintLabelForeground = Color.white

  // Destructive actions
  static let destructiveAction = Color.red

  // Auto-hide panels
  static let panelOverlayShadow = bg.opacity(0.1)
  static let autoHideHint = Color.primary.opacity(0.2)

  // Transparent
  static let transparent = Color.clear
}
