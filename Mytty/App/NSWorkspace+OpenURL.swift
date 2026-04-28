import AppKit
import UniformTypeIdentifiers

/// Resolve a raw URL string from libghostty into a `URL`.
/// Strings with a scheme (http, file, etc.) are used as-is.
/// Schemeless strings are treated as file paths with tilde expansion.
func resolveOpenURL(_ urlString: String) -> URL {
  if let candidate = URL(string: urlString), candidate.scheme != nil {
    return candidate
  }
  let expandedPath = NSString(string: urlString).standardizingPath
  return URL(filePath: expandedPath)
}

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
