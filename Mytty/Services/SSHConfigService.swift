import Foundation

struct SSHHost: Sendable {
  let alias: String
  let hostname: String?
}

struct SSHConfigService {
  static func parse(_ content: String) -> [SSHHost] {
    var hosts: [SSHHost] = []
    var currentAlias: String?
    var currentHostname: String?

    for line in content.components(separatedBy: .newlines) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      let lower = trimmed.lowercased()

      if lower.hasPrefix("host ") {
        if let alias = currentAlias, !alias.contains("*") {
          hosts.append(SSHHost(alias: alias, hostname: currentHostname))
        }
        currentAlias = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        currentHostname = nil
      } else if lower.hasPrefix("hostname ") {
        currentHostname = String(trimmed.dropFirst(9)).trimmingCharacters(in: .whitespaces)
      }
    }

    if let alias = currentAlias, !alias.contains("*") {
      hosts.append(SSHHost(alias: alias, hostname: currentHostname))
    }

    return hosts
  }

  static func loadHosts() -> [SSHHost] {
    let sshDir = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".ssh")
    let configURL = sshDir.appendingPathComponent("config")
    guard let content = try? String(contentsOf: configURL, encoding: .utf8) else { return [] }
    return parseWithIncludes(content, baseDir: sshDir, depth: 0)
  }

  private static func parseWithIncludes(_ content: String, baseDir: URL, depth: Int) -> [SSHHost] {
    guard depth < 5 else { return [] }
    var hosts = parse(content)
    for line in content.components(separatedBy: .newlines) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard trimmed.lowercased().hasPrefix("include ") else { continue }
      let pattern = String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespaces)
      let resolved =
        pattern.hasPrefix("/")
        ? pattern
        : baseDir.appendingPathComponent(pattern).path
      for path in expandGlob(resolved) {
        guard let included = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
        let includeDir = URL(fileURLWithPath: path).deletingLastPathComponent()
        hosts.append(contentsOf: parseWithIncludes(included, baseDir: includeDir, depth: depth + 1))
      }
    }
    return hosts
  }

  private static func expandGlob(_ pattern: String) -> [String] {
    let expanded = (pattern as NSString).expandingTildeInPath
    var gt = glob_t()
    defer { globfree(&gt) }
    guard glob(expanded, GLOB_TILDE | GLOB_BRACE, nil, &gt) == 0 else { return [] }
    return (0..<Int(gt.gl_pathc)).compactMap { i in
      gt.gl_pathv[i].flatMap { String(cString: $0) }
    }
  }
}
