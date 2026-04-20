import Testing

@testable import Mytty

@MainActor
@Suite("MyttyPane")
struct MyttyPaneTests {

  // MARK: - buildInitialInput

  @Test func buildInitialInput_noCommand_returnsNil() {
    let result = MyttyPane.buildInitialInput(command: nil, useCommandField: true)
    #expect(result == nil)
  }

  @Test func buildInitialInput_noCommand_closeOnExit_returnsNil() {
    let result = MyttyPane.buildInitialInput(command: nil, useCommandField: false)
    #expect(result == nil)
  }

  @Test func buildInitialInput_emptyCommand_returnsNil() {
    let result = MyttyPane.buildInitialInput(command: "", useCommandField: true)
    #expect(result == nil)
  }

  @Test func buildInitialInput_emptyCommand_closeOnExit_returnsNil() {
    let result = MyttyPane.buildInitialInput(command: "", useCommandField: false)
    #expect(result == nil)
  }

  @Test func buildInitialInput_keepOnExit_returnsCommandWithoutExec() {
    let result = MyttyPane.buildInitialInput(command: "ls", useCommandField: true)
    #expect(result == "ls")
  }

  @Test func buildInitialInput_closeOnExit_returnsCommandWithExec() {
    let result = MyttyPane.buildInitialInput(command: "ls", useCommandField: false)
    #expect(result == "exec ls")
  }

  @Test func buildInitialInput_keepOnExit_preservesArguments() {
    let result = MyttyPane.buildInitialInput(command: "ls -la /tmp", useCommandField: true)
    #expect(result == "ls -la /tmp")
  }

  @Test func buildInitialInput_closeOnExit_preservesArguments() {
    let result = MyttyPane.buildInitialInput(command: "ls -la /tmp", useCommandField: false)
    #expect(result == "exec ls -la /tmp")
  }

  @Test func buildInitialInput_keepOnExit_commandWithSpaces() {
    let result = MyttyPane.buildInitialInput(command: "echo hello world", useCommandField: true)
    #expect(result == "echo hello world")
  }

  @Test func buildInitialInput_closeOnExit_commandWithSpaces() {
    let result = MyttyPane.buildInitialInput(command: "echo hello world", useCommandField: false)
    #expect(result == "exec echo hello world")
  }
}
