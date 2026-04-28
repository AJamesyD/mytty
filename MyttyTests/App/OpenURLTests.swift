import Foundation
import Testing

@testable import Mytty

struct OpenURLTests {
  @Test func schemeURL_usedAsIs() {
    let url = resolveOpenURL("https://example.com/page")
    #expect(url.scheme == "https")
    #expect(url.absoluteString == "https://example.com/page")
  }

  @Test func fileScheme_usedAsIs() {
    let url = resolveOpenURL("file:///tmp/foo.txt")
    #expect(url.scheme == "file")
    #expect(url.path == "/tmp/foo.txt")
  }

  @Test func absolutePath_becomesFileURL() {
    let url = resolveOpenURL("/tmp/foo.txt")
    #expect(url.isFileURL)
    #expect(url.path == "/tmp/foo.txt")
  }

  @Test func tildePath_expanded() {
    let url = resolveOpenURL("~/Documents/config.toml")
    #expect(url.isFileURL)
    #expect(!url.path.contains("~"))
    #expect(url.path.hasSuffix("/Documents/config.toml"))
  }

  @Test func spaceInFilename_becomesFileURL() {
    let url = resolveOpenURL("/tmp/my file.txt")
    #expect(url.isFileURL)
    #expect(url.path.contains("my file.txt"))
  }

  @Test func colonPort_treatedAsScheme() {
    // "localhost:8080" parses as scheme "localhost" — matches Ghostty behavior
    let url = resolveOpenURL("localhost:8080")
    #expect(url.scheme == "localhost")
  }
}
