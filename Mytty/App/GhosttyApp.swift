import AppKit
import GhosttyKit

// MARK: - C Callbacks (top-level, no captures)

/// Called from a background thread when ghostty needs attention.
/// Must dispatch to main thread.
private let wakeupCallback: ghostty_runtime_wakeup_cb = { userdata in
  guard let userdata else { return }
  let manager = Unmanaged<GhosttyAppManager>.fromOpaque(userdata).takeUnretainedValue()
  DispatchQueue.main.async {
    manager.tick()
  }
}

/// Resolves the surface's TerminalSurfaceView on the main thread and calls the body.
private nonisolated func withSurfaceView(
  _ target: ghostty_target_s,
  body: @escaping @MainActor (TerminalSurfaceView) -> Void
) {
  guard target.tag == GHOSTTY_TARGET_SURFACE else { return }
  let surface = target.target.surface
  DispatchQueue.main.async {
    guard let userdata = ghostty_surface_userdata(surface) else { return }
    let view = Unmanaged<TerminalSurfaceView>.fromOpaque(userdata).takeUnretainedValue()
    body(view)
  }
}

/// Called when ghostty wants the apprt to perform an action.
private let actionCallback: ghostty_runtime_action_cb = { _, target, action in
  switch action.tag {
  case GHOSTTY_ACTION_RENDER:
    return true

  case GHOSTTY_ACTION_SET_TITLE:
    if let title = action.action.set_title.title {
      let titleStr = String(cString: title)
      withSurfaceView(target) { view in
        NotificationCenter.default.post(
          name: .ghosttySetTitle,
          object: nil,
          userInfo: [Notification.payloadKey: SetTitlePayload(paneID: view.pane?.id, title: titleStr)]
        )
      }
    }
    return true

  case GHOSTTY_ACTION_CLOSE_WINDOW:
    return true

  // CELL_SIZE: read on-demand via ghostty_surface_size(); no cached property to update
  case GHOSTTY_ACTION_CELL_SIZE,
    GHOSTTY_ACTION_SIZE_LIMIT,
    GHOSTTY_ACTION_INITIAL_SIZE,
    GHOSTTY_ACTION_MOUSE_SHAPE,
    GHOSTTY_ACTION_MOUSE_VISIBILITY:
    return true

  case GHOSTTY_ACTION_RING_BELL:
    withSurfaceView(target) { view in
      NotificationCenter.default.post(
        name: .ghosttyRingBell,
        object: nil,
        userInfo: [Notification.payloadKey: PanePayload(paneID: view.pane?.id)]
      )
    }
    return true

  case GHOSTTY_ACTION_SCROLLBAR:
    let sb = action.action.scrollbar
    withSurfaceView(target) { view in
      view.scrollbarState = ScrollbarState(total: sb.total, offset: sb.offset, len: sb.len)
    }
    return true

  case GHOSTTY_ACTION_PWD:
    guard let pwd = action.action.pwd.pwd else { return true }
    let pwdStr = String(cString: pwd)
    withSurfaceView(target) { view in
      NotificationCenter.default.post(
        name: .ghosttyPwd,
        object: nil,
        userInfo: [Notification.payloadKey: PwdPayload(paneID: view.pane?.id, pwd: pwdStr)]
      )
    }
    return true

  case GHOSTTY_ACTION_SET_TAB_TITLE:
    guard let title = action.action.set_tab_title.title else { return true }
    let titleStr = String(cString: title)
    withSurfaceView(target) { view in
      NotificationCenter.default.post(
        name: .ghosttySetTabTitle,
        object: nil,
        userInfo: [Notification.payloadKey: SetTitlePayload(paneID: view.pane?.id, title: titleStr)]
      )
    }
    return true

  case GHOSTTY_ACTION_DESKTOP_NOTIFICATION:
    guard let title = action.action.desktop_notification.title,
      let body = action.action.desktop_notification.body
    else { return true }
    let titleStr = String(cString: title)
    let bodyStr = String(cString: body)
    withSurfaceView(target) { view in
      NotificationCenter.default.post(
        name: .ghosttyDesktopNotification,
        object: nil,
        userInfo: [
          Notification.payloadKey: DesktopNotificationPayload(paneID: view.pane?.id, title: titleStr, body: bodyStr),
        ]
      )
    }
    return true

  case GHOSTTY_ACTION_COMMAND_FINISHED:
    let exitCode = action.action.command_finished.exit_code
    let duration = action.action.command_finished.duration
    withSurfaceView(target) { view in
      NotificationCenter.default.post(
        name: .ghosttyCommandFinished,
        object: nil,
        userInfo: [
          Notification.payloadKey: CommandFinishedPayload(paneID: view.pane?.id, exitCode: exitCode, duration: duration),
        ]
      )
    }
    return true

  case GHOSTTY_ACTION_PROGRESS_REPORT:
    let report = action.action.progress_report
    let state: ProgressReportPayload.State
    switch report.state {
    case GHOSTTY_PROGRESS_STATE_SET: state = .set
    case GHOSTTY_PROGRESS_STATE_ERROR: state = .error
    case GHOSTTY_PROGRESS_STATE_INDETERMINATE: state = .indeterminate
    case GHOSTTY_PROGRESS_STATE_PAUSE: state = .pause
    case GHOSTTY_PROGRESS_STATE_REMOVE: state = .remove
    default: return false
    }
    withSurfaceView(target) { view in
      NotificationCenter.default.post(
        name: .ghosttyProgressReport,
        object: nil,
        userInfo: [
          Notification.payloadKey: ProgressReportPayload(paneID: view.pane?.id, state: state, progress: report.progress),
        ]
      )
    }
    return true

  case GHOSTTY_ACTION_COLOR_CHANGE:
    let change = action.action.color_change
    let kind: ColorChangePayload.Kind = switch change.kind {
    case GHOSTTY_ACTION_COLOR_KIND_BACKGROUND: .background
    case GHOSTTY_ACTION_COLOR_KIND_FOREGROUND: .foreground
    case GHOSTTY_ACTION_COLOR_KIND_CURSOR: .cursor
    default: .palette
    }
    let r = CGFloat(change.r) / 255.0
    let g = CGFloat(change.g) / 255.0
    let b = CGFloat(change.b) / 255.0
    withSurfaceView(target) { view in
      NotificationCenter.default.post(
        name: .ghosttyColorChange,
        object: nil,
        userInfo: [
          Notification.payloadKey: ColorChangePayload(
            paneID: view.pane?.id, kind: kind, r: r, g: g, b: b),
        ]
      )
    }
    return true

  // TODO(phase-6): clone config and propagate to derive NSAppearance and scrollbar style
  case GHOSTTY_ACTION_CONFIG_CHANGE:
    return true

  // Category B: actions that map to Mytty operations

  case GHOSTTY_ACTION_NEW_TAB:
    withSurfaceView(target) { view in
      NotificationCenter.default.post(
        name: .ghosttyNewTab,
        object: nil,
        userInfo: [Notification.payloadKey: PanePayload(paneID: view.pane?.id)]
      )
    }
    return true

  case GHOSTTY_ACTION_NEW_SPLIT:
    let raw = action.action.new_split
    let direction: SplitDirection =
      (raw == GHOSTTY_SPLIT_DIRECTION_DOWN || raw == GHOSTTY_SPLIT_DIRECTION_UP)
      ? .vertical : .horizontal
    withSurfaceView(target) { view in
      NotificationCenter.default.post(
        name: .ghosttyNewSplit,
        object: nil,
        userInfo: [
          Notification.payloadKey: NewSplitPayload(paneID: view.pane?.id, direction: direction),
        ]
      )
    }
    return true

  case GHOSTTY_ACTION_CLOSE_TAB:
    withSurfaceView(target) { view in
      NotificationCenter.default.post(
        name: .ghosttyCloseTab,
        object: nil,
        userInfo: [Notification.payloadKey: PanePayload(paneID: view.pane?.id)]
      )
    }
    return true

  case GHOSTTY_ACTION_GOTO_SPLIT:
    let raw = action.action.goto_split
    let direction: GotoSplitDirection
    switch raw {
    case GHOSTTY_GOTO_SPLIT_PREVIOUS: direction = .previous
    case GHOSTTY_GOTO_SPLIT_NEXT: direction = .next
    case GHOSTTY_GOTO_SPLIT_UP: direction = .spatial(.up)
    case GHOSTTY_GOTO_SPLIT_DOWN: direction = .spatial(.down)
    case GHOSTTY_GOTO_SPLIT_LEFT: direction = .spatial(.left)
    case GHOSTTY_GOTO_SPLIT_RIGHT: direction = .spatial(.right)
    default: return false
    }
    withSurfaceView(target) { view in
      NotificationCenter.default.post(
        name: .ghosttyGotoSplit,
        object: nil,
        userInfo: [
          Notification.payloadKey: GotoSplitPayload(paneID: view.pane?.id, direction: direction),
        ]
      )
    }
    return true

  case GHOSTTY_ACTION_RESIZE_SPLIT:
    let resize = action.action.resize_split
    let direction: NavigationDirection
    switch resize.direction {
    case GHOSTTY_RESIZE_SPLIT_UP: direction = .up
    case GHOSTTY_RESIZE_SPLIT_DOWN: direction = .down
    case GHOSTTY_RESIZE_SPLIT_LEFT: direction = .left
    case GHOSTTY_RESIZE_SPLIT_RIGHT: direction = .right
    default: return false
    }
    withSurfaceView(target) { view in
      NotificationCenter.default.post(
        name: .ghosttyResizeSplit,
        object: nil,
        userInfo: [
          Notification.payloadKey: ResizeSplitPayload(paneID: view.pane?.id, amount: resize.amount, direction: direction),
        ]
      )
    }
    return true

  case GHOSTTY_ACTION_EQUALIZE_SPLITS:
    withSurfaceView(target) { view in
      NotificationCenter.default.post(
        name: .ghosttyEqualizeSplits,
        object: nil,
        userInfo: [Notification.payloadKey: PanePayload(paneID: view.pane?.id)]
      )
    }
    return true

  case GHOSTTY_ACTION_TOGGLE_SPLIT_ZOOM:
    withSurfaceView(target) { view in
      NotificationCenter.default.post(
        name: .ghosttyToggleSplitZoom,
        object: nil,
        userInfo: [Notification.payloadKey: PanePayload(paneID: view.pane?.id)]
      )
    }
    return true

  case GHOSTTY_ACTION_GOTO_TAB:
    let tab = action.action.goto_tab
    withSurfaceView(target) { view in
      NotificationCenter.default.post(
        name: .ghosttyGotoTab,
        object: nil,
        userInfo: [
          Notification.payloadKey: GotoTabPayload(paneID: view.pane?.id, tab: tab.rawValue),
        ]
      )
    }
    return true

  case GHOSTTY_ACTION_MOVE_TAB:
    let amount = action.action.move_tab.amount
    withSurfaceView(target) { view in
      NotificationCenter.default.post(
        name: .ghosttyMoveTab,
        object: nil,
        userInfo: [
          Notification.payloadKey: MoveTabPayload(paneID: view.pane?.id, amount: amount),
        ]
      )
    }
    return true

  case GHOSTTY_ACTION_TOGGLE_FULLSCREEN:
    DispatchQueue.main.async {
      NSApp.keyWindow?.toggleFullScreen(nil)
    }
    return true

  case GHOSTTY_ACTION_OPEN_URL:
    let openUrl = action.action.open_url
    if let urlPtr = openUrl.url {
      let urlStr = String(cString: urlPtr)
      DispatchQueue.main.async {
        if let url = URL(string: urlStr) {
          NSWorkspace.shared.open(url)
        }
      }
    }
    return true

  case GHOSTTY_ACTION_TOGGLE_QUICK_TERMINAL:
    DispatchQueue.main.async {
      NotificationCenter.default.post(
        name: .ghosttyToggleQuickTerminal,
        object: nil
      )
    }
    return true

  case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
    let exitCode = action.action.child_exited.exit_code
    withSurfaceView(target) { view in
      NotificationCenter.default.post(
        name: .ghosttyChildExited,
        object: nil,
        userInfo: [
          Notification.payloadKey: ChildExitedPayload(paneID: view.pane?.id, exitCode: exitCode),
        ]
      )
    }
    return true

  case GHOSTTY_ACTION_RELOAD_CONFIG:
    DispatchQueue.main.async {
      GhosttyAppManager.shared.reloadGhosttyConfig()
    }
    return true

  case GHOSTTY_ACTION_KEY_TABLE:
    let raw = action.action.key_table
    let keyAction: KeyTablePayload.Action
    switch raw.tag {
    case GHOSTTY_KEY_TABLE_ACTIVATE:
      let name = String(
        bytes: Data(bytes: raw.value.activate.name, count: raw.value.activate.len),
        encoding: .utf8) ?? ""
      keyAction = .activate(name: name)
    case GHOSTTY_KEY_TABLE_DEACTIVATE:
      keyAction = .deactivate
    case GHOSTTY_KEY_TABLE_DEACTIVATE_ALL:
      keyAction = .deactivateAll
    default: return false
    }
    withSurfaceView(target) { view in
      NotificationCenter.default.post(
        name: .ghosttyKeyTable,
        object: nil,
        userInfo: [
          Notification.payloadKey: KeyTablePayload(paneID: view.pane?.id, action: keyAction),
        ]
      )
    }
    return true

  // Category C: acknowledged, no Mytty equivalent
  case GHOSTTY_ACTION_QUIT,
    GHOSTTY_ACTION_CHECK_FOR_UPDATES,
    GHOSTTY_ACTION_SHOW_GTK_INSPECTOR,
    GHOSTTY_ACTION_PRESENT_TERMINAL,
    GHOSTTY_ACTION_READONLY,
    GHOSTTY_ACTION_START_SEARCH,
    GHOSTTY_ACTION_END_SEARCH,
    GHOSTTY_ACTION_SEARCH_TOTAL,
    GHOSTTY_ACTION_SEARCH_SELECTED,
    GHOSTTY_ACTION_CLOSE_ALL_WINDOWS,
    GHOSTTY_ACTION_NEW_WINDOW,
    GHOSTTY_ACTION_GOTO_WINDOW,
    GHOSTTY_ACTION_FLOAT_WINDOW,
    GHOSTTY_ACTION_TOGGLE_MAXIMIZE,
    GHOSTTY_ACTION_TOGGLE_TAB_OVERVIEW,
    GHOSTTY_ACTION_TOGGLE_VISIBILITY,
    GHOSTTY_ACTION_TOGGLE_WINDOW_DECORATIONS,
    GHOSTTY_ACTION_TOGGLE_BACKGROUND_OPACITY,
    GHOSTTY_ACTION_TOGGLE_COMMAND_PALETTE,
    GHOSTTY_ACTION_RESET_WINDOW_SIZE,
    GHOSTTY_ACTION_INSPECTOR,
    GHOSTTY_ACTION_RENDER_INSPECTOR,
    GHOSTTY_ACTION_PROMPT_TITLE,
    GHOSTTY_ACTION_QUIT_TIMER,
    GHOSTTY_ACTION_SECURE_INPUT,
    GHOSTTY_ACTION_KEY_SEQUENCE,
    GHOSTTY_ACTION_OPEN_CONFIG,
    GHOSTTY_ACTION_RENDERER_HEALTH,
    GHOSTTY_ACTION_MOUSE_OVER_LINK,
    GHOSTTY_ACTION_COPY_TITLE_TO_CLIPBOARD,
    GHOSTTY_ACTION_SHOW_ON_SCREEN_KEYBOARD,
    GHOSTTY_ACTION_UNDO,
    GHOSTTY_ACTION_REDO:
    return true

  default:
    return false
  }
}

/// Clipboard read callback.
private let readClipboardCallback: ghostty_runtime_read_clipboard_cb = {
  userdata, clipboard, state in
  guard let userdata, let state else { return false }
  let view = Unmanaged<TerminalSurfaceView>.fromOpaque(userdata).takeUnretainedValue()
  guard let surface = view.surface else { return false }
  let pasteboard =
    clipboard == GHOSTTY_CLIPBOARD_SELECTION
    ? NSPasteboard(name: .init("com.mitchellh.ghostty.selection"))
    : NSPasteboard.general
  guard let str = pasteboard.string(forType: .string) else { return false }
  str.withCString { ptr in
    ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
  }
  return true
}

/// Clipboard confirm read callback (auto-confirms).
private let confirmReadClipboardCallback: ghostty_runtime_confirm_read_clipboard_cb = {
  userdata, str, state, _ in
  guard let userdata, let state, let str else { return }
  let view = Unmanaged<TerminalSurfaceView>.fromOpaque(userdata).takeUnretainedValue()
  guard let surface = view.surface else { return }
  ghostty_surface_complete_clipboard_request(surface, str, state, true)
}

/// Clipboard write callback.
private let writeClipboardCallback: ghostty_runtime_write_clipboard_cb = {
  _, _, content, count, _ in
  guard let content, count > 0 else { return }
  let pasteboard = NSPasteboard.general
  pasteboard.clearContents()
  if let data = content.pointee.data {
    pasteboard.setString(String(cString: data), forType: .string)
  }
}

/// Close surface callback: shell exited.
private let closeSurfaceCallback: ghostty_runtime_close_surface_cb = { userdata, _ in
  guard let userdata else { return }
  let view = Unmanaged<TerminalSurfaceView>.fromOpaque(userdata).takeUnretainedValue()
  DispatchQueue.main.async {
    NotificationCenter.default.post(
      name: .ghosttyCloseSurface,
      object: nil,
      userInfo: [Notification.payloadKey: PanePayload(paneID: view.pane?.id)]
    )
  }
}

// MARK: - Notification Names

extension Notification.Name {
  static let ghosttySetTitle = Notification.Name("ghosttySetTitle")
  static let ghosttyCloseSurface = Notification.Name("ghosttyCloseSurface")
  static let ghosttyRingBell = Notification.Name("ghosttyRingBell")
  static let ghosttyPwd = Notification.Name("ghosttyPwd")
  static let ghosttySetTabTitle = Notification.Name("ghosttySetTabTitle")
  static let ghosttyDesktopNotification = Notification.Name("ghosttyDesktopNotification")
  static let ghosttyCommandFinished = Notification.Name("ghosttyCommandFinished")
  static let ghosttyProgressReport = Notification.Name("ghosttyProgressReport")
  static let ghosttyColorChange = Notification.Name("ghosttyColorChange")
  static let ghosttyNewTab = Notification.Name("ghosttyNewTab")
  static let ghosttyNewSplit = Notification.Name("ghosttyNewSplit")
  static let ghosttyCloseTab = Notification.Name("ghosttyCloseTab")
  static let ghosttyGotoSplit = Notification.Name("ghosttyGotoSplit")
  static let ghosttyResizeSplit = Notification.Name("ghosttyResizeSplit")
  static let ghosttyEqualizeSplits = Notification.Name("ghosttyEqualizeSplits")
  static let ghosttyToggleSplitZoom = Notification.Name("ghosttyToggleSplitZoom")
  static let ghosttyGotoTab = Notification.Name("ghosttyGotoTab")
  static let ghosttyMoveTab = Notification.Name("ghosttyMoveTab")
  static let ghosttyToggleQuickTerminal = Notification.Name("ghosttyToggleQuickTerminal")
  static let ghosttyChildExited = Notification.Name("ghosttyChildExited")
  static let ghosttyKeyTable = Notification.Name("ghosttyKeyTable")
}

// MARK: - Notification Payloads

extension Notification {
  static let payloadKey = "payload"

  func payload<T>(_ type: T.Type) -> T? {
    userInfo?[Self.payloadKey] as? T
  }
}

struct PanePayload {
  let paneID: Int?
}

struct SetTitlePayload {
  let paneID: Int?
  let title: String
}

struct PwdPayload {
  let paneID: Int?
  let pwd: String
}

struct DesktopNotificationPayload {
  let paneID: Int?
  let title: String
  let body: String
}

struct CommandFinishedPayload {
  let paneID: Int?
  let exitCode: Int16
  let duration: UInt64
}

struct ProgressReportPayload {
  enum State {
    case set, error, indeterminate, pause, remove
  }
  let paneID: Int?
  let state: State
  let progress: Int8
}

struct NewSplitPayload {
  let paneID: Int?
  let direction: SplitDirection
}

struct GotoSplitPayload {
  let paneID: Int?
  let direction: GotoSplitDirection
}

struct ResizeSplitPayload {
  let paneID: Int?
  let amount: UInt16
  let direction: NavigationDirection
}

struct GotoTabPayload {
  let paneID: Int?
  let tab: Int32
}

struct MoveTabPayload {
  let paneID: Int?
  let amount: Int
}

struct ChildExitedPayload {
  let paneID: Int?
  let exitCode: UInt32
}

struct KeyTablePayload {
  enum Action {
    case activate(name: String)
    case deactivate
    case deactivateAll
  }
  let paneID: Int?
  let action: Action
}

struct ColorChangePayload {
  enum Kind {
    case background
    case foreground
    case cursor
    case palette
  }
  let paneID: Int?
  let kind: Kind
  let r: CGFloat
  let g: CGFloat
  let b: CGFloat
}

// MARK: - GhosttyAppManager

@MainActor
final class GhosttyAppManager {
  static let shared = GhosttyAppManager()

  nonisolated(unsafe) private(set) var app: ghostty_app_t?
  nonisolated(unsafe) private var config: ghostty_config_t?
  private var appearanceObserver: NSKeyValueObservation?

  private init() {
    // 1. Initialize ghostty
    let initResult = ghostty_init(0, nil)
    guard initResult == GHOSTTY_SUCCESS else {
      print("[GhosttyAppManager] ghostty_init failed: \(initResult)")
      return
    }

    // 2. Create and load config
    guard let cfg = ghostty_config_new() else {
      print("[GhosttyAppManager] ghostty_config_new failed")
      return
    }

    // Load Ghostty config as base (fonts, colors, theme carry over).
    // Ghostty 1.3+ uses config.ghostty; older versions use config. Load both if present.
    let ghosttyConfigDir = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config/ghostty")
    for filename in ["config", "config.ghostty"] {
      let path = ghosttyConfigDir.appendingPathComponent(filename).path
      if FileManager.default.fileExists(atPath: path) {
        path.withCString { cPath in
          ghostty_config_load_file(cfg, cPath)
        }
      }
    }

    // Process config-file directives from the base Ghostty config
    ghostty_config_load_recursive_files(cfg)

    // Mytty overrides (optional, takes precedence over Ghostty config)
    let myttyConfigPath = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config/mytty/ghostty.conf").path
    if FileManager.default.fileExists(atPath: myttyConfigPath) {
      myttyConfigPath.withCString { path in
        ghostty_config_load_file(cfg, path)
      }
    }
    ghostty_config_finalize(cfg)
    self.config = cfg

    // Log any config diagnostics
    let diagCount = ghostty_config_diagnostics_count(cfg)
    for i in 0..<diagCount {
      let diag = ghostty_config_get_diagnostic(cfg, i)
      if let msg = diag.message {
        print("[GhosttyAppManager] config diagnostic: \(String(cString: msg))")
      }
    }

    // 3. Build runtime config with C callbacks
    let selfPtr = Unmanaged.passUnretained(self).toOpaque()
    var runtimeCfg = ghostty_runtime_config_s(
      userdata: selfPtr,
      supports_selection_clipboard: false,
      wakeup_cb: wakeupCallback,
      action_cb: actionCallback,
      read_clipboard_cb: readClipboardCallback,
      confirm_read_clipboard_cb: confirmReadClipboardCallback,
      write_clipboard_cb: writeClipboardCallback,
      close_surface_cb: closeSurfaceCallback
    )

    // 4. Create the app
    self.app = ghostty_app_new(&runtimeCfg, cfg)
    if self.app == nil {
      print("[GhosttyAppManager] ghostty_app_new failed")
    }

    // 5. Sync dark/light mode to libghostty
    if let app = self.app {
      appearanceObserver = NSApplication.shared.observe(
        \.effectiveAppearance, options: [.new, .initial]
      ) { _, change in
        guard let appearance = change.newValue else { return }
        let scheme: ghostty_color_scheme_e =
          appearance.name.rawValue.lowercased().contains("dark")
          ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT
        ghostty_app_set_color_scheme(app, scheme)
      }
    }
  }

  deinit {
    if let app { ghostty_app_free(app) }
    if let config { ghostty_config_free(config) }
  }

  struct WindowConfig {
    let decorations: Bool
    let titlebarStyle: String
    let windowButtons: String

    init(config: ghostty_config_t?) {
      guard let cfg = config else {
        self.decorations = true
        self.titlebarStyle = "transparent"
        self.windowButtons = "visible"
        return
      }

      var decPtr: UnsafePointer<Int8>?
      let decKey = "window-decoration"
      if ghostty_config_get(cfg, &decPtr, decKey, UInt(decKey.lengthOfBytes(using: .utf8))),
        let ptr = decPtr {
        let str = String(cString: ptr)
        self.decorations = (str != "none" && str != "false")
      } else {
        self.decorations = true
      }

      var tsPtr: UnsafePointer<Int8>?
      let tsKey = "macos-titlebar-style"
      if ghostty_config_get(cfg, &tsPtr, tsKey, UInt(tsKey.lengthOfBytes(using: .utf8))),
        let ptr = tsPtr {
        self.titlebarStyle = String(cString: ptr)
      } else {
        self.titlebarStyle = "transparent"
      }

      var wbPtr: UnsafePointer<Int8>?
      let wbKey = "macos-window-buttons"
      if ghostty_config_get(cfg, &wbPtr, wbKey, UInt(wbKey.lengthOfBytes(using: .utf8))),
        let ptr = wbPtr {
        self.windowButtons = String(cString: ptr)
      } else {
        self.windowButtons = "visible"
      }
    }
  }

  var windowConfig: WindowConfig { WindowConfig(config: config) }

  func reloadGhosttyConfig() {
    guard let app else { return }
    guard let cfg = ghostty_config_new() else { return }

    let ghosttyConfigDir = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config/ghostty")
    for filename in ["config", "config.ghostty"] {
      let path = ghosttyConfigDir.appendingPathComponent(filename).path
      if FileManager.default.fileExists(atPath: path) {
        path.withCString { cPath in
          ghostty_config_load_file(cfg, cPath)
        }
      }
    }

    ghostty_config_load_recursive_files(cfg)

    let myttyConfigPath = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config/mytty/ghostty.conf").path
    if FileManager.default.fileExists(atPath: myttyConfigPath) {
      myttyConfigPath.withCString { path in
        ghostty_config_load_file(cfg, path)
      }
    }
    ghostty_config_finalize(cfg)

    let diagCount = ghostty_config_diagnostics_count(cfg)
    for i in 0..<diagCount {
      let diag = ghostty_config_get_diagnostic(cfg, i)
      if let msg = diag.message {
        print("[GhosttyAppManager] config diagnostic: \(String(cString: msg))")
      }
    }

    ghostty_app_update_config(app, cfg)
    let oldConfig = self.config
    self.config = cfg
    if let old = oldConfig { ghostty_config_free(old) }
  }

  func tick() {
    guard let app else { return }
    ghostty_app_tick(app)
  }
}
