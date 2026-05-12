import AppKit
import GhosttyKit
import SwiftUI

@MainActor @Observable
// Key handler + motion execution for copy mode. Splitting would separate key dispatch from its effects.
final class CopyModeManager {
  private(set) var isActive = false
  private var store: SessionStore?
  var onNeedExitWindowMode: () -> Void = {}

  struct CopyModeKey: Hashable {
    let key: String
    let hasCtrl: Bool
  }

  private var triggerToAction: [CopyModeKey: String] = [:]

  // Maps action name to the canonical (character, hasCtrl) that CopyModeState expects
  private static let actionToCanonical: [String: (Character, Bool)] = [
    "move-left": ("h", false),
    "move-down": ("j", false),
    "move-up": ("k", false),
    "move-right": ("l", false),
    "line-start": ("0", false),
    "line-end": ("$", false),
    "bottom": ("G", false),
    "visual": ("v", false),
    "visual-line": ("V", false),
    "word-forward": ("w", false),
    "word-forward-big": ("W", false),
    "word-backward": ("b", false),
    "word-backward-big": ("B", false),
    "word-end": ("e", false),
    "word-end-big": ("E", false),
    "search-forward": ("/", false),
    "search-backward": ("?", false),
    "search-next": ("n", false),
    "search-prev": ("N", false),
    "find-char": ("f", false),
    "find-char-back": ("F", false),
    "find-till": ("t", false),
    "find-till-back": ("T", false),
    "repeat-find": (";", false),
    "repeat-find-back": (",", false),
    "half-page-down": ("d", true),
    "half-page-up": ("u", true),
    "page-down": ("f", true),
    "page-up": ("b", true),
    "yank": ("y", false),
  ]

  private func loadBindings() {
    let keybindingStore = MyttyConfig.load().keybindingStore
    triggerToAction = [:]
    let reverseMap = keybindingStore.reverseLookup(in: .copyMode)
    for (trigger, action) in reverseMap {
      let cmKey = CopyModeKey(
        key: trigger.key,
        hasCtrl: trigger.modifiers.contains(.ctrl)
      )
      triggerToAction[cmKey] = action
    }
  }

  func setBindingsForTesting(_ bindings: [String: String]) {
    triggerToAction = [:]
    for (key, action) in bindings {
      let cmKey = CopyModeKey(key: key, hasCtrl: false)
      triggerToAction[cmKey] = action
    }
  }

  func shouldTranslate(_ state: CopyModeState, key: Character, keyCode: UInt16) -> Bool {
    if state.showingHelp { return false }
    if keyCode == 53 { return false }
    if state.isSearching { return false }
    if state.pendingFindChar != nil { return false }
    if state.pendingG { return false }
    if let digit = key.wholeNumberValue, digit != 0 || state.pendingCount != nil { return false }
    return true
  }

  func translateKey(
    _ key: Character, modifiers: NSEvent.ModifierFlags, state: CopyModeState, keyCode: UInt16
  ) -> (Character, NSEvent.ModifierFlags) {
    guard shouldTranslate(state, key: key, keyCode: keyCode) else {
      return (key, modifiers)
    }
    let cmKey = CopyModeKey(key: String(key), hasCtrl: modifiers.contains(.control))
    guard let action = triggerToAction[cmKey],
      let (canonicalKey, canonicalCtrl) = Self.actionToCanonical[action]
    else {
      return (key, modifiers)
    }
    var newMods = modifiers
    if canonicalCtrl {
      newMods.insert(.control)
    } else {
      newMods.remove(.control)
    }
    return (canonicalKey, newMods)
  }

  func enter(store: SessionStore) {
    guard !isActive else { return }
    guard let tab = store.activeSession?.activeTab else { return }
    if tab.isWindowModeActive {
      onNeedExitWindowMode()
    }

    self.store = store
    isActive = true
    loadBindings()

    var rows = 24
    var cols = 80
    var cursorRow: Int?
    var cursorCol: Int?
    if let surfaceView = tab.activePane?.surfaceView {
      if let surface = surfaceView.surface {
        let size = ghostty_surface_size(surface)
        rows = Int(size.rows)
        cols = Int(size.columns)
      }
      if let pos = surfaceView.cursorPosition() {
        cursorRow = pos.row
        cursorCol = pos.col
      }
    }

    tab.copyModeState = CopyModeState(
      rows: rows, cols: cols, cursorRow: cursorRow, cursorCol: cursorCol)
  }

  func exit() {
    // Scroll back to bottom (active area) when leaving copy mode
    if let pane = store?.activeSession?.activeTab?.activePane,
      let surface = pane.surfaceView.surface
    {
      let actionStr = "scroll_to_bottom"
      _ = ghostty_surface_binding_action(surface, actionStr, UInt(actionStr.utf8.count))
    }
    store?.activeSession?.activeTab?.copyModeState = nil
    store = nil
    isActive = false
  }

  func deactivate() {
    guard isActive else { return }
    exit()
  }

  func handleKeyDown(_ event: NSEvent) -> NSEvent? {
    guard var state = store?.activeSession?.activeTab?.copyModeState
    else { return event }

    if event.modifierFlags.contains(.command) && !state.isSearching {
      return nil
    }

    guard let keyStr = event.charactersIgnoringModifiers, let key = keyStr.first else {
      return event
    }

    let lineReader: (Int) -> String? = { row in
      self.readTerminalLine(row: row)
    }

    let (effectiveKey, effectiveModifiers) = translateKey(
      key, modifiers: event.modifierFlags, state: state, keyCode: event.keyCode)

    let actions = state.handleKey(
      key: effectiveKey,
      keyCode: event.keyCode,
      modifiers: effectiveModifiers,
      lineReader: lineReader
    )

    for action in actions {
      switch action {
      case .cursorMoved:
        break
      case .updateSelection:
        break
      case .yank:
        break
      case .exitCopyMode:
        if state.isSelecting {
          store?.activeSession?.activeTab?.copyModeState = state
          yankSelection()
        }
        exit()
        return nil
      case .enterSubMode:
        break
      case .showHelp, .hideHelp:
        break
      case .startSearch:
        break
      case .updateSearch:
        break
      case .confirmSearch:
        performSearch(&state, direction: state.searchDirection)
        countSearchMatches(&state)
      case .cancelSearch:
        break
      case .searchNext:
        performSearch(&state, direction: state.searchDirection)
        countSearchMatches(&state)
      case .searchPrev:
        let reversed: SearchDirection = state.searchDirection == .forward ? .reverse : .forward
        performSearch(&state, direction: reversed)
        countSearchMatches(&state)
      case .scroll(let deltaRows):
        scrollViewport(&state, delta: deltaRows)
      case .needsContinuation:
        var pending = true
        var iterations = 0
        while pending && iterations < 100 {
          iterations += 1
          pending = false
          let continuationActions = state.continuePendingMotion(lineReader: lineReader)
          for contAction in continuationActions {
            switch contAction {
            case .scroll(let delta):
              scrollViewport(&state, delta: delta)
            case .needsContinuation:
              pending = true
            default:
              break
            }
          }
        }
      }
    }

    store?.activeSession?.activeTab?.copyModeState = state
    return nil
  }

  private func scrollViewport(_ state: inout CopyModeState, delta: Int) {
    guard let pane = store?.activeSession?.activeTab?.activePane,
      let surface = pane.surfaceView.surface
    else { return }
    let actionStr = "scroll_page_lines:\(delta)"
    _ = ghostty_surface_binding_action(surface, actionStr, UInt(actionStr.utf8.count))
    // Update scrollbar offset synchronously, the async callback will
    // eventually arrive, but we need correct offset immediately for
    // subsequent search coordinate conversion.
    let newOffset = Int64(pane.surfaceView.scrollbarState.offset) + Int64(delta)
    pane.surfaceView.scrollbarState.offset = UInt64(max(0, newOffset))
    if let anchor = state.anchor {
      state.anchor = (row: anchor.row - delta, col: anchor.col)
    }
    state.scrollGeneration &+= 1
  }

  private func performSearch(_ state: inout CopyModeState, direction: SearchDirection) {
    guard !state.searchQuery.isEmpty,
      let pane = store?.activeSession?.activeTab?.activePane,
      let surface = pane.surfaceView.surface
    else { return }

    let scrollbar = pane.surfaceView.scrollbarState
    let totalRows = Int(scrollbar.total)
    let viewportOffset = Int(scrollbar.offset)
    let cols = Int(ghostty_surface_size(surface).columns)
    guard totalRows > 0 else { return }

    let cursorScreenRow = state.cursorRow + viewportOffset
    let isForward = direction == .forward

    // Search all rows, starting from the current row.
    // On the current row, only consider matches AFTER (forward) or BEFORE (reverse) the cursor.
    for i in 0...totalRows {
      let screenRow: Int
      if isForward {
        screenRow = (cursorScreenRow + i) % totalRows
      } else {
        screenRow = (cursorScreenRow - i + totalRows) % totalRows
      }

      guard let line = readLineByScreenRow(screenRow) else { continue }

      let matchCol: Int?
      if i == 0 {
        matchCol = findMatchOnLine(
          line, query: state.searchQuery, cursorCol: state.cursorCol, forward: isForward)
      } else {
        matchCol = findMatchOnLine(
          line, query: state.searchQuery, cursorCol: isForward ? -1 : Int.max, forward: isForward)
      }

      if let col = matchCol {
        // Scroll to make the match visible, center it in viewport
        let viewportRows = Int(scrollbar.len)
        let targetOffset = max(0, min(screenRow - viewportRows / 2, totalRows - viewportRows))
        let actionStr = "scroll_to_row:\(targetOffset)"
        _ = ghostty_surface_binding_action(surface, actionStr, UInt(actionStr.utf8.count))

        // Update scrollbar state synchronously, the async callback will
        // eventually arrive with the same value, but we need it now for
        // subsequent searches (n/N) to compute correct screen coordinates.
        pane.surfaceView.scrollbarState.offset = UInt64(targetOffset)

        state.cursorRow = screenRow - targetOffset
        state.cursorCol = min(col, cols - 1)
        state.desiredCol = nil
        return
      }
    }
  }

  func findMatchOnLine(
    _ line: String, query: String, cursorCol: Int, forward: Bool
  ) -> Int? {
    var bestCol: Int?
    var searchStart = line.startIndex
    while let range = line.range(
      of: query, options: .caseInsensitive, range: searchStart..<line.endIndex)
    {
      let col = line.distance(from: line.startIndex, to: range.lowerBound)
      if forward {
        if col > cursorCol {
          return col
        }
      } else {
        if col < cursorCol {
          bestCol = col
        }
      }
      searchStart = range.upperBound
    }
    return bestCol
  }

  private func countSearchMatches(_ state: inout CopyModeState) {
    guard !state.searchQuery.isEmpty,
      let pane = store?.activeSession?.activeTab?.activePane
    else { return }

    let scrollbar = pane.surfaceView.scrollbarState
    let totalRows = Int(scrollbar.total)
    let viewportOffset = Int(scrollbar.offset)
    let cursorScreenRow = state.cursorRow + viewportOffset

    var total = 0
    var currentIndex = 0

    for row in 0..<totalRows {
      guard let line = readLineByScreenRow(row) else { continue }
      var searchStart = line.startIndex
      while let range = line.range(
        of: state.searchQuery, options: .caseInsensitive,
        range: searchStart..<line.endIndex)
      {
        total += 1
        let matchCol = line.distance(from: line.startIndex, to: range.lowerBound)
        if row < cursorScreenRow || (row == cursorScreenRow && matchCol <= state.cursorCol) {
          currentIndex = total
        }
        searchStart = range.upperBound
      }
    }

    state.searchMatchTotal = total > 0 ? total : nil
    state.searchMatchIndex = total > 0 ? currentIndex : nil
  }

  private func readTerminalLine(row: Int) -> String? {
    guard let pane = store?.activeSession?.activeTab?.activePane,
      let surface = pane.surfaceView.surface
    else { return nil }

    let size = ghostty_surface_size(surface)

    var sel = ghostty_selection_s()
    sel.top_left.tag = GHOSTTY_POINT_VIEWPORT
    sel.top_left.coord = GHOSTTY_POINT_COORD_EXACT
    sel.top_left.x = 0
    sel.top_left.y = UInt32(row)
    sel.bottom_right.tag = GHOSTTY_POINT_VIEWPORT
    sel.bottom_right.coord = GHOSTTY_POINT_COORD_EXACT
    sel.bottom_right.x = UInt32(size.columns - 1)
    sel.bottom_right.y = UInt32(row)
    sel.rectangle = false

    var text = ghostty_text_s()
    guard ghostty_surface_read_text(surface, sel, &text) else { return nil }
    defer { ghostty_surface_free_text(surface, &text) }
    guard let ptr = text.text else { return nil }
    return String(cString: ptr)
  }

  private func readLineByScreenRow(_ screenRow: Int) -> String? {
    guard let pane = store?.activeSession?.activeTab?.activePane else { return nil }
    let scrollbar = pane.surfaceView.scrollbarState
    let viewportRow = screenRow - Int(scrollbar.offset)
    if viewportRow >= 0 && viewportRow < Int(scrollbar.len) {
      return readTerminalLine(row: viewportRow)
    }
    return readScreenLine(row: screenRow)
  }

  private func readScreenLine(row: Int) -> String? {
    guard let pane = store?.activeSession?.activeTab?.activePane,
      let surface = pane.surfaceView.surface
    else { return nil }

    let size = ghostty_surface_size(surface)

    var sel = ghostty_selection_s()
    sel.top_left.tag = GHOSTTY_POINT_SCREEN
    sel.top_left.coord = GHOSTTY_POINT_COORD_EXACT
    sel.top_left.x = 0
    sel.top_left.y = UInt32(row)
    sel.bottom_right.tag = GHOSTTY_POINT_SCREEN
    sel.bottom_right.coord = GHOSTTY_POINT_COORD_EXACT
    sel.bottom_right.x = UInt32(size.columns - 1)
    sel.bottom_right.y = UInt32(row)
    sel.rectangle = false

    var text = ghostty_text_s()
    guard ghostty_surface_read_text(surface, sel, &text) else { return nil }
    defer { ghostty_surface_free_text(surface, &text) }
    guard let ptr = text.text else { return nil }
    return String(cString: ptr)
  }

  private func yankSelection() {
    guard let tab = store?.activeSession?.activeTab,
      let pane = tab.activePane,
      let state = tab.copyModeState,
      let anchor = state.anchor,
      let surface = pane.surfaceView.surface
    else { return }

    let size = ghostty_surface_size(surface)
    let cols = Int(size.columns)
    var textToCopy: String?

    let anchorOutOfViewport = anchor.row < 0 || anchor.row >= state.rows
    let useScreenCoords = anchorOutOfViewport
    let tag: ghostty_point_tag_e = useScreenCoords ? GHOSTTY_POINT_SCREEN : GHOSTTY_POINT_VIEWPORT
    let offset = useScreenCoords ? Int(pane.surfaceView.scrollbarState.offset) : 0

    switch state.subMode {
    case .visual:
      textToCopy = readGhosttyText(
        surface: surface,
        startRow: anchor.row + offset, startCol: anchor.col,
        endRow: state.cursorRow + offset, endCol: state.cursorCol,
        rectangle: false,
        pointTag: tag
      )

    case .visualLine:
      let minRow = min(anchor.row, state.cursorRow)
      let maxRow = max(anchor.row, state.cursorRow)
      textToCopy = readGhosttyText(
        surface: surface,
        startRow: minRow + offset, startCol: 0,
        endRow: maxRow + offset, endCol: cols - 1,
        rectangle: false,
        pointTag: tag
      )

    case .visualBlock:
      let minRow = min(anchor.row, state.cursorRow)
      let maxRow = max(anchor.row, state.cursorRow)
      let minCol = min(anchor.col, state.cursorCol)
      var lines: [String] = []
      let logicalRightCol = max(anchor.col, state.cursorCol)
      for row in minRow...maxRow {
        let readRow = row + offset
        let line: String?
        if useScreenCoords {
          line = readScreenLine(row: readRow)
        } else {
          line = readTerminalLine(row: readRow)
        }
        if let line {
          let contentEnd = WordMotion.lastNonWhitespaceIndex(in: line)
          guard contentEnd >= minCol else {
            lines.append("")
            continue
          }
          let rightCol = min(logicalRightCol, contentEnd)
          let chars = Array(line)
          let start = min(minCol, chars.count)
          let end = min(rightCol + 1, chars.count)
          if start < end {
            lines.append(String(chars[start..<end]))
          } else {
            lines.append("")
          }
        }
      }
      textToCopy = lines.joined(separator: "\n")

    default:
      return
    }

    if let text = textToCopy, !text.isEmpty {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
    }
  }

  private func readGhosttyText(
    surface: ghostty_surface_t,
    startRow: Int, startCol: Int,
    endRow: Int, endCol: Int,
    rectangle: Bool,
    pointTag: ghostty_point_tag_e = GHOSTTY_POINT_VIEWPORT
  ) -> String? {
    var sel = ghostty_selection_s()
    sel.top_left.tag = pointTag
    sel.top_left.coord = GHOSTTY_POINT_COORD_EXACT
    sel.top_left.x = UInt32(startCol)
    sel.top_left.y = UInt32(startRow)
    sel.bottom_right.tag = pointTag
    sel.bottom_right.coord = GHOSTTY_POINT_COORD_EXACT
    sel.bottom_right.x = UInt32(endCol)
    sel.bottom_right.y = UInt32(endRow)
    sel.rectangle = rectangle

    var text = ghostty_text_s()
    guard ghostty_surface_read_text(surface, sel, &text) else { return nil }
    defer { ghostty_surface_free_text(surface, &text) }
    guard let ptr = text.text else { return nil }
    return String(cString: ptr)
  }
}
