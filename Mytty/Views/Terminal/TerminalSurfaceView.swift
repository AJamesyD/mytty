import AppKit
import GhosttyKit
import MyttyShared

final class TerminalSurfaceView: NSView {
  nonisolated(unsafe) private(set) var surface: ghostty_surface_t?
  var onSelect: (() -> Void)?
  @MainActor static var keyDispatch: ((NSEvent) -> NSEvent?)?
  @MainActor static var modalKeyHandler: ((NSEvent) -> NSEvent?)?
  var scrollbarState = ScrollbarState()

  /// Back-reference to the owning pane (set by MyttyPane).
  weak var pane: MyttyPane?
  private var cursorShape: NSCursor = .iBeam
  private(set) var cursorVisible: Bool = true

  init(
    frame: NSRect, workingDirectory: URL? = nil, initialInput: String? = nil,
    sessionID: Int = 0, sessionName: String = "", tabID: Int = 0, paneID: Int = 0
  ) {
    super.init(frame: frame)
    wantsLayer = true

    guard let app = GhosttyAppManager.shared.app else {
      print("[TerminalSurfaceView] No ghostty app available")
      return
    }

    var cfg = ghostty_surface_config_new()
    cfg.platform_tag = GHOSTTY_PLATFORM_MACOS
    cfg.platform = ghostty_platform_u(
      macos: ghostty_platform_macos_s(
        nsview: Unmanaged.passUnretained(self).toOpaque()
      )
    )
    cfg.userdata = Unmanaged.passUnretained(self).toOpaque()
    cfg.scale_factor = Double(NSScreen.main?.backingScaleFactor ?? 2.0)
    cfg.context = GHOSTTY_SURFACE_CONTEXT_WINDOW

    // Commands are always sent via initial_input (not cfg.command) to avoid
    // ghostty's macOS login shell wrapper which breaks non-shell programs.
    // The caller (MyttyPane.buildInitialInput) handles any exec wrapping.
    let dirPtr = workingDirectory.flatMap { strdup($0.path) }
    let inputPtr = initialInput.flatMap { strdup("\($0)\n") }
    defer {
      if let p = dirPtr { free(p) }
      if let p = inputPtr { free(p) }
    }

    cfg.working_directory = UnsafePointer(dirPtr)
    cfg.initial_input = UnsafePointer(inputPtr)

    var envVars = [
      ghostty_env_var_s(key: strdup("MYTTY_SOCKET"), value: strdup(MyttyIPC.socketPath)),
      ghostty_env_var_s(key: strdup("TERM_PROGRAM"), value: strdup("mytty")),
      ghostty_env_var_s(key: strdup("MYTTY"), value: strdup("1")),
      ghostty_env_var_s(
        key: strdup("MYTTY_VERSION"),
        value: strdup(
          Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0")),
      ghostty_env_var_s(key: strdup("MYTTY_SESSION_ID"), value: strdup(String(sessionID))),
      ghostty_env_var_s(key: strdup("MYTTY_SESSION_NAME"), value: strdup(sessionName)),
      ghostty_env_var_s(key: strdup("MYTTY_TAB_ID"), value: strdup(String(tabID))),
      ghostty_env_var_s(key: strdup("MYTTY_PANE_ID"), value: strdup(String(paneID))),
    ]
    envVars.withUnsafeMutableBufferPointer { buffer in
      cfg.env_vars = buffer.baseAddress
      cfg.env_var_count = buffer.count
      surface = ghostty_surface_new(app, &cfg)
    }
    for env in envVars {
      free(UnsafeMutablePointer(mutating: env.key))
      free(UnsafeMutablePointer(mutating: env.value))
    }

    if surface == nil {
      print("[TerminalSurfaceView] ghostty_surface_new failed")
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("Not implemented") }

  deinit {
    NotificationCenter.default.removeObserver(self)
    if let surface { ghostty_surface_free(surface) }
  }

  // MARK: - Responder

  override var acceptsFirstResponder: Bool { true }

  // Match Ghostty's SurfaceView_AppKit.swift: respect super's result
  // before notifying libghostty of focus changes.
  override func becomeFirstResponder() -> Bool {
    let result = super.becomeFirstResponder()
    if result, let surface { ghostty_surface_set_focus(surface, true) }
    return result
  }

  override func resignFirstResponder() -> Bool {
    let result = super.resignFirstResponder()
    if result, let surface { ghostty_surface_set_focus(surface, false) }
    return result
  }

  // MARK: - Grid Metrics

  struct GridMetrics {
    var cellWidth: CGFloat
    var cellHeight: CGFloat
    var offsetX: CGFloat
    var offsetY: CGFloat
  }

  /// Returns cell dimensions in points and the grid's top-left offset within the view.
  func gridMetrics() -> GridMetrics? {
    guard let surface else { return nil }
    let size = ghostty_surface_size(surface)
    guard size.cell_width_px > 0, size.cell_height_px > 0 else { return nil }
    let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
    let cellW = CGFloat(size.cell_width_px) / scale
    let cellH = CGFloat(size.cell_height_px) / scale
    // Derive grid origin from ime_point: the cursor at column C has x = offsetX + C * cellW,
    // so offsetX = x % cellW (padding is always less than one cell width).
    // Falls back to Ghostty's default 2pt padding if ime_point returns zeros.
    var imeX: Double = 0
    var imeY: Double = 0
    var imeW: Double = 0
    var imeH: Double = 0
    ghostty_surface_ime_point(surface, &imeX, &imeY, &imeW, &imeH)
    let offsetX: CGFloat
    let offsetY: CGFloat
    if imeX > 0, cellW > 0 {
      offsetX = CGFloat(imeX).truncatingRemainder(dividingBy: cellW)
    } else {
      offsetX = 2.0
    }
    if imeY > 0, cellH > 0 {
      offsetY = CGFloat(imeY - imeH).truncatingRemainder(dividingBy: cellH)
    } else {
      offsetY = 2.0
    }
    return GridMetrics(cellWidth: cellW, cellHeight: cellH, offsetX: offsetX, offsetY: offsetY)
  }

  /// Returns the terminal cursor position as (row, col) in grid coordinates.
  func cursorPosition() -> (row: Int, col: Int)? {
    guard let surface else { return nil }
    var x: Double = 0
    var y: Double = 0
    var w: Double = 0
    var h: Double = 0
    ghostty_surface_ime_point(surface, &x, &y, &w, &h)
    guard let metrics = gridMetrics() else { return nil }
    // ime_point returns point coordinates (not pixels).
    // y points to the bottom of the cursor cell, so subtract one cell height.
    let col = Int((CGFloat(x) - metrics.offsetX) / metrics.cellWidth)
    let row = Int((CGFloat(y) - metrics.offsetY - metrics.cellHeight) / metrics.cellHeight)
    let size = ghostty_surface_size(surface)
    return (row: max(0, min(row, Int(size.rows) - 1)), col: max(0, min(col, Int(size.columns) - 1)))
  }

  // MARK: - Layout

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    guard let surface, let window else { return }
    let scale = window.backingScaleFactor
    let w = UInt32(newSize.width * scale)
    let h = UInt32(newSize.height * scale)
    ghostty_surface_set_size(surface, w, h)
    ghostty_surface_set_content_scale(surface, Double(scale), Double(scale))
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard window != nil else { return }
    setFrameSize(frame.size)
    window?.makeFirstResponder(self)

    // Remove first to avoid duplicate registrations if the view moves between windows.
    NotificationCenter.default.removeObserver(
      self, name: NSWindow.didChangeScreenNotification, object: nil)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowDidChangeScreen(_:)),
      name: NSWindow.didChangeScreenNotification,
      object: nil)

    if let surface, let displayID = window?.screen?.displayID {
      ghostty_surface_set_display_id(surface, displayID)
    }
  }

  // Matches Ghostty's SurfaceView_AppKit.swift screen-change handling.
  @objc private func windowDidChangeScreen(_ notification: Notification) {
    guard let window = self.window else { return }
    guard let object = notification.object as? NSWindow, window == object else { return }
    guard let screen = window.screen else { return }
    guard let surface = self.surface else { return }
    ghostty_surface_set_display_id(surface, screen.displayID ?? 0)
    // DispatchQueue (not Task) to match Ghostty's run-loop timing for backing property updates.
    // Ref: vendor/ghostty/macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift
    DispatchQueue.main.async { [weak self] in self?.viewDidChangeBackingProperties() }
  }

  // Handle display DPI changes when moving between monitors.
  // Matches Ghostty's SurfaceView_AppKit.swift viewDidChangeBackingProperties.
  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    if let window {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      layer?.contentsScale = window.backingScaleFactor
      CATransaction.commit()
    }
    guard let surface, window != nil else { return }
    let fbFrame = convertToBacking(frame)
    let xScale = fbFrame.size.width / frame.size.width
    let yScale = fbFrame.size.height / frame.size.height
    ghostty_surface_set_content_scale(surface, xScale, yScale)
    let scaledSize = convertToBacking(frame.size)
    ghostty_surface_set_size(surface, UInt32(scaledSize.width), UInt32(scaledSize.height))
  }

  // MARK: - Keyboard Input

  /// Accumulates text from interpretKeyEvents → insertText
  private var keyTextAccumulator: [String]?
  private var markedText = NSMutableAttributedString()

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard event.type == .keyDown else { return false }
    guard event.modifierFlags.contains(.command) else { return false }
    if let mainMenu = NSApp.mainMenu, mainMenu.performKeyEquivalent(with: event) {
      return true
    }
    return false
  }

  override func keyDown(with event: NSEvent) {
    guard let surface else { return }

    if KeyEventDebug.enabled {
      KeyEventDebug.log("Surface.keyDown", event)
    }

    if let modal = Self.modalKeyHandler, modal(event) == nil {
      return
    }

    if let dispatch = Self.keyDispatch, dispatch(event) == nil {
      return
    }

    let action: ghostty_input_action_e =
      event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS

    // Translate modifiers for option-as-alt config support.
    // ghostty_surface_key_translation_mods reads the config internally and
    // returns translated modifier flags (e.g., Option removed).
    let translationModsGhostty = eventModifierFlags(
      mods: ghostty_surface_key_translation_mods(
        surface,
        ghosttyMods(event.modifierFlags)
      )
    )

    // Preserve hidden bits in the original flags that matter for dead keys.
    // Only update the four standard modifier flags from the translation result.
    var translationMods = event.modifierFlags
    for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command] {
      if translationModsGhostty.contains(flag) {
        translationMods.insert(flag)
      } else {
        translationMods.remove(flag)
      }
    }

    // Reuse the original event when mods are unchanged to preserve AppKit
    // identity (required for input methods like Korean).
    let translationEvent: NSEvent
    if translationMods == event.modifierFlags {
      translationEvent = event
    } else {
      translationEvent =
        NSEvent.keyEvent(
          with: event.type,
          location: event.locationInWindow,
          modifierFlags: translationMods,
          timestamp: event.timestamp,
          windowNumber: event.windowNumber,
          context: nil,
          characters: event.characters(byApplyingModifiers: translationMods) ?? "",
          charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
          isARepeat: event.isARepeat,
          keyCode: event.keyCode
        ) ?? event
    }

    // Use interpretKeyEvents to get OS-resolved text (handles keyboard layouts, dead keys, IME)
    keyTextAccumulator = []
    defer { keyTextAccumulator = nil }

    let markedTextBefore = markedText.length > 0
    let keyboardIdBefore: String? =
      if !markedTextBefore {
        NSTextInputContext.current?.selectedKeyboardInputSource
      } else {
        nil
      }
    interpretKeyEvents([translationEvent])

    if KeyEventDebug.enabled {
      KeyEventDebug.print("Surface.interpret: text=\(keyTextAccumulator ?? [])")
    }

    if !markedTextBefore,
      let idBefore = keyboardIdBefore,
      idBefore != NSTextInputContext.current?.selectedKeyboardInputSource
    {
      return
    }

    syncPreedit(clearIfNeeded: markedTextBefore)

    if keyTextAccumulator?.isEmpty != false {
      // No text produced (e.g. Escape, arrows, function keys) — send key event only
      var keyEvent = event.ghosttyKeyEvent(action, translationMods: translationEvent.modifierFlags)
      keyEvent.composing = markedText.length > 0 || markedTextBefore
      _ = ghostty_surface_key(surface, keyEvent)
    } else {
      // Skip text for control characters (< 0x20); libghostty encodes
      // them itself. Without this, ctrl+enter breaks (SurfaceView_AppKit.swift).
      for text in keyTextAccumulator ?? [] {
        var keyEvent = event.ghosttyKeyEvent(
          action, translationMods: translationEvent.modifierFlags)
        if let codepoint = text.utf8.first, codepoint >= 0x20 {
          text.withCString { ptr in
            keyEvent.text = ptr
            _ = ghostty_surface_key(surface, keyEvent)
          }
        } else {
          _ = ghostty_surface_key(surface, keyEvent)
        }
      }
    }
  }

  override func keyUp(with event: NSEvent) {
    guard let surface else { return }
    let keyEvent = event.ghosttyKeyEvent(GHOSTTY_ACTION_RELEASE)
    _ = ghostty_surface_key(surface, keyEvent)
  }

  override func flagsChanged(with event: NSEvent) {
    guard let surface else { return }
    if hasMarkedText() { return }

    // Determine if this modifier key is being pressed or released
    let mod: UInt32
    switch event.keyCode {
    case 0x39: mod = GHOSTTY_MODS_CAPS.rawValue
    case 0x38, 0x3C: mod = GHOSTTY_MODS_SHIFT.rawValue
    case 0x3B, 0x3E: mod = GHOSTTY_MODS_CTRL.rawValue
    case 0x3A, 0x3D: mod = GHOSTTY_MODS_ALT.rawValue
    case 0x37, 0x36: mod = GHOSTTY_MODS_SUPER.rawValue
    default: return
    }

    // Right-side modifier keys (0x3C, 0x3E, 0x3D, 0x36) need side-specific
    // checks to distinguish press from release when the opposite side is held.
    // Matches Ghostty's SurfaceView_AppKit.swift flagsChanged.
    var action: ghostty_input_action_e = GHOSTTY_ACTION_RELEASE
    if ghosttyMods(event.modifierFlags).rawValue & mod != 0 {
      let sidePressed: Bool
      switch event.keyCode {
      case 0x3C:
        sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERSHIFTKEYMASK) != 0
      case 0x3E:
        sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERCTLKEYMASK) != 0
      case 0x3D:
        sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERALTKEYMASK) != 0
      case 0x36:
        sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERCMDKEYMASK) != 0
      default:
        sidePressed = true
      }
      if sidePressed {
        action = GHOSTTY_ACTION_PRESS
      }
    }
    let keyEvent = event.ghosttyKeyEvent(action)
    _ = ghostty_surface_key(surface, keyEvent)
  }

  override func doCommand(by selector: Selector) {
    // Intentionally empty: prevents NSBeep when interpretKeyEvents
    // dispatches selectors (insertTab:, insertNewline:, etc.) that
    // have no handler in the responder chain.
  }

  private func syncPreedit(clearIfNeeded: Bool = true) {
    guard let surface else { return }
    if markedText.length > 0 {
      let str = markedText.string
      let len = str.utf8CString.count
      if len > 0 {
        str.withCString { ptr in
          ghostty_surface_preedit(surface, ptr, UInt(len - 1))
        }
      }
    } else if clearIfNeeded {
      ghostty_surface_preedit(surface, nil, 0)
    }
  }
}

// MARK: - Mouse Input

extension TerminalSurfaceView {
  // Divergence: Ghostty uses NSScrollView.documentCursor (observed via Combine
  // on SurfaceScrollView). Mytty has no scroll view wrapper, so we use
  // resetCursorRects directly. See Ghostty SurfaceScrollView.swift line 149.
  override func resetCursorRects() {
    addCursorRect(bounds, cursor: cursorShape)
  }

  func setCursorShape(_ shape: ghostty_action_mouse_shape_e) {
    // Ghostty uses #available(macOS 15.0, *) for resize cursors because it
    // targets macOS 13 (Cursor.swift). Mytty targets macOS 15+, so we use
    // the new APIs directly.
    switch shape {
    case GHOSTTY_MOUSE_SHAPE_DEFAULT: cursorShape = .arrow
    case GHOSTTY_MOUSE_SHAPE_TEXT: cursorShape = .iBeam
    case GHOSTTY_MOUSE_SHAPE_GRAB: cursorShape = .openHand
    case GHOSTTY_MOUSE_SHAPE_GRABBING: cursorShape = .closedHand
    case GHOSTTY_MOUSE_SHAPE_POINTER: cursorShape = .pointingHand
    case GHOSTTY_MOUSE_SHAPE_W_RESIZE: cursorShape = .columnResize(directions: .left)
    case GHOSTTY_MOUSE_SHAPE_E_RESIZE: cursorShape = .columnResize(directions: .right)
    case GHOSTTY_MOUSE_SHAPE_N_RESIZE: cursorShape = .rowResize(directions: .up)
    case GHOSTTY_MOUSE_SHAPE_S_RESIZE: cursorShape = .rowResize(directions: .down)
    case GHOSTTY_MOUSE_SHAPE_NS_RESIZE: cursorShape = .rowResize
    case GHOSTTY_MOUSE_SHAPE_EW_RESIZE: cursorShape = .columnResize
    case GHOSTTY_MOUSE_SHAPE_VERTICAL_TEXT: cursorShape = .iBeamCursorForVerticalLayout
    case GHOSTTY_MOUSE_SHAPE_CONTEXT_MENU: cursorShape = .contextualMenu
    case GHOSTTY_MOUSE_SHAPE_CROSSHAIR: cursorShape = .crosshair
    case GHOSTTY_MOUSE_SHAPE_NOT_ALLOWED: cursorShape = .operationNotAllowed
    default: return
    }
    window?.invalidateCursorRects(for: self)
  }

  func setCursorVisibility(_ visible: Bool) {
    cursorVisible = visible
    NSCursor.setHiddenUntilMouseMoves(!visible)
  }

  // Divergence: Mytty syncs mouse position before button events. Ghostty
  // does not. This ensures libghostty has the correct cursor position when
  // processing the button press, avoiding stale coordinates after fast moves.
  override func mouseDown(with event: NSEvent) {
    onSelect?()
    guard let surface else { return }
    let point = convert(event.locationInWindow, from: nil)
    ghostty_surface_mouse_pos(
      surface, Double(point.x), Double(frame.height - point.y), ghosttyMods(event.modifierFlags))
    _ = ghostty_surface_mouse_button(
      surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, ghosttyMods(event.modifierFlags))
  }

  override func mouseUp(with event: NSEvent) {
    guard let surface else { return }
    let point = convert(event.locationInWindow, from: nil)
    ghostty_surface_mouse_pos(
      surface, Double(point.x), Double(frame.height - point.y), ghosttyMods(event.modifierFlags))
    _ = ghostty_surface_mouse_button(
      surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, ghosttyMods(event.modifierFlags))
  }

  override func mouseMoved(with event: NSEvent) {
    guard let surface else { return }
    let point = convert(event.locationInWindow, from: nil)
    ghostty_surface_mouse_pos(
      surface, Double(point.x), Double(frame.height - point.y), ghosttyMods(event.modifierFlags))
  }

  override func mouseDragged(with event: NSEvent) {
    mouseMoved(with: event)
  }

  override func rightMouseDown(with event: NSEvent) {
    guard let surface else { return super.rightMouseDown(with: event) }
    let point = convert(event.locationInWindow, from: nil)
    let mods = ghosttyMods(event.modifierFlags)
    ghostty_surface_mouse_pos(surface, Double(point.x), Double(frame.height - point.y), mods)
    if !ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, mods) {
      super.rightMouseDown(with: event)
    }
  }

  override func rightMouseUp(with event: NSEvent) {
    guard let surface else { return super.rightMouseUp(with: event) }
    let point = convert(event.locationInWindow, from: nil)
    let mods = ghosttyMods(event.modifierFlags)
    ghostty_surface_mouse_pos(surface, Double(point.x), Double(frame.height - point.y), mods)
    if !ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, mods) {
      super.rightMouseUp(with: event)
    }
  }

  override func otherMouseDown(with event: NSEvent) {
    guard let surface else { return }
    let point = convert(event.locationInWindow, from: nil)
    let mods = ghosttyMods(event.modifierFlags)
    ghostty_surface_mouse_pos(surface, Double(point.x), Double(frame.height - point.y), mods)
    let btn = ghosttyMouseButton(event.buttonNumber)
    _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, btn, mods)
  }

  override func otherMouseUp(with event: NSEvent) {
    guard let surface else { return }
    let point = convert(event.locationInWindow, from: nil)
    let mods = ghosttyMods(event.modifierFlags)
    ghostty_surface_mouse_pos(surface, Double(point.x), Double(frame.height - point.y), mods)
    let btn = ghosttyMouseButton(event.buttonNumber)
    _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, btn, mods)
  }

  override func rightMouseDragged(with event: NSEvent) {
    mouseMoved(with: event)
  }

  override func otherMouseDragged(with event: NSEvent) {
    mouseMoved(with: event)
  }

  override func scrollWheel(with event: NSEvent) {
    guard let surface else { return }

    let precision = event.hasPreciseScrollingDeltas
    var x = event.scrollingDeltaX
    var y = event.scrollingDeltaY
    // Match Ghostty's 2x multiplier for trackpad deltas (SurfaceView_AppKit.swift)
    if precision {
      x *= 2
      y *= 2
    }

    let momentum: Int32 =
      switch event.momentumPhase {
      case .began: 1
      case .stationary: 2
      case .changed: 3
      case .ended: 4
      case .cancelled: 5
      case .mayBegin: 6
      default: 0
      }

    let scrollMods: ghostty_input_scroll_mods_t = (precision ? 1 : 0) | (momentum << 1)
    ghostty_surface_mouse_scroll(surface, x, y, scrollMods)
  }

  private func ghosttyMouseButton(_ buttonNumber: Int) -> ghostty_input_mouse_button_e {
    switch buttonNumber {
    case 0: return GHOSTTY_MOUSE_LEFT
    case 1: return GHOSTTY_MOUSE_RIGHT
    case 2: return GHOSTTY_MOUSE_MIDDLE
    case 3: return GHOSTTY_MOUSE_EIGHT
    case 4: return GHOSTTY_MOUSE_NINE
    case 5: return GHOSTTY_MOUSE_SIX
    case 6: return GHOSTTY_MOUSE_SEVEN
    case 7: return GHOSTTY_MOUSE_FOUR
    case 8: return GHOSTTY_MOUSE_FIVE
    case 9: return GHOSTTY_MOUSE_TEN
    case 10: return GHOSTTY_MOUSE_ELEVEN
    default: return GHOSTTY_MOUSE_UNKNOWN
    }
  }
}

// MARK: - NSTextInputClient

extension TerminalSurfaceView: @preconcurrency NSTextInputClient {
  func insertText(_ string: Any, replacementRange: NSRange) {
    guard NSApp.currentEvent != nil else { return }
    let str: String
    if let s = string as? String {
      str = s
    } else if let attrStr = string as? NSAttributedString {
      str = attrStr.string
    } else {
      str = String(describing: string)
    }
    unmarkText()
    if var acc = keyTextAccumulator {
      acc.append(str)
      keyTextAccumulator = acc
      return
    }
  }

  func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
    switch string {
    case let v as NSAttributedString:
      self.markedText = NSMutableAttributedString(attributedString: v)
    case let v as String:
      self.markedText = NSMutableAttributedString(string: v)
    default:
      return
    }
    if keyTextAccumulator == nil {
      syncPreedit()
    }
  }

  func unmarkText() {
    if markedText.length > 0 {
      markedText.mutableString.setString("")
      syncPreedit()
    }
  }

  func selectedRange() -> NSRange {
    NSRange(location: NSNotFound, length: 0)
  }

  func markedRange() -> NSRange {
    guard markedText.length > 0 else { return NSRange(location: NSNotFound, length: 0) }
    return NSRange(0...(markedText.length - 1))
  }

  func hasMarkedText() -> Bool { markedText.length > 0 }

  func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?)
    -> NSAttributedString?
  {
    nil
  }

  func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

  func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
    guard let surface else { return .zero }
    var x: Double = 0
    var y: Double = 0
    var w: Double = 0
    var h: Double = 0
    ghostty_surface_ime_point(surface, &x, &y, &w, &h)
    let viewPoint = NSPoint(x: x, y: frame.height - y)
    guard let window else { return NSRect(origin: viewPoint, size: NSSize(width: w, height: h)) }
    let windowPoint = convert(viewPoint, to: nil)
    let screenPoint = window.convertPoint(toScreen: windowPoint)
    return NSRect(origin: screenPoint, size: NSSize(width: w, height: h))
  }

  func characterIndex(for point: NSPoint) -> Int { 0 }
}
