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

  init(
    frame: NSRect, workingDirectory: URL? = nil, command: String? = nil, initialInput: String? = nil
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

    // Use strdup to pin optional C strings for the config struct.
    // The env vars already use this pattern a few lines below.
    // For popups that should close on exit, send the command as initial_input
    // instead of cfg.command. ghostty forces wait-after-command=true when
    // cfg.command is set, which shows "press any key to close". Using
    // initial_input runs the command in the shell naturally.
    let dirPtr = workingDirectory.flatMap { strdup($0.path) }
    let cmdPtr = command.flatMap { strdup($0) }
    let inputPtr = initialInput.flatMap { strdup("exec \($0)\n") }
    defer {
      if let p = dirPtr { free(p) }
      if let p = cmdPtr { free(p) }
      if let p = inputPtr { free(p) }
    }

    cfg.working_directory = UnsafePointer(dirPtr)
    cfg.command = UnsafePointer(cmdPtr)
    cfg.initial_input = UnsafePointer(inputPtr)

    var envVars = [
      ghostty_env_var_s(key: strdup("MYTTY_SOCKET"), value: strdup(MyttyIPC.socketPath)),
      ghostty_env_var_s(key: strdup("TERM_PROGRAM"), value: strdup("mytty")),
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
    if let surface { ghostty_surface_free(surface) }
  }

  // MARK: - Responder

  override var acceptsFirstResponder: Bool { true }

  override func becomeFirstResponder() -> Bool {
    if let surface { ghostty_surface_set_focus(surface, true) }
    return true
  }

  override func resignFirstResponder() -> Bool {
    if let surface { ghostty_surface_set_focus(surface, false) }
    return true
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
      // Send key event with accumulated text
      for text in keyTextAccumulator ?? [] {
        var keyEvent = event.ghosttyKeyEvent(
          action, translationMods: translationEvent.modifierFlags)
        text.withCString { ptr in
          keyEvent.text = ptr
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

    let pressed = ghosttyMods(event.modifierFlags).rawValue & mod != 0
    let action: ghostty_input_action_e = pressed ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
    let keyEvent = event.ghosttyKeyEvent(action)
    _ = ghostty_surface_key(surface, keyEvent)
  }

  // MARK: - Mouse Input

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

  override func scrollWheel(with event: NSEvent) {
    guard let surface else { return }
    ghostty_surface_mouse_scroll(surface, event.scrollingDeltaX, event.scrollingDeltaY, 0)
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
