import AppKit
import UniformTypeIdentifiers

extension NSWorkspace {
  var defaultTextEditor: URL? {
    defaultApplicationURL(forContentType: UTType.plainText.identifier)
  }

  func defaultApplicationURL(forContentType contentType: String) -> URL? {
    LSCopyDefaultApplicationURLForContentType(
      contentType as CFString,
      .all,
      nil
    )?.takeRetainedValue() as? URL
  }

  func defaultApplicationURL(forExtension ext: String) -> URL? {
    guard let uti = UTType(filenameExtension: ext) else { return nil }
    return defaultApplicationURL(forContentType: uti.identifier)
  }
}
