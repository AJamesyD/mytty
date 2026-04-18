import SwiftUI

struct SettingsView: View {
  private let config = MyttyConfig.load()

  var body: some View {
    Form {
      Section("Appearance") {
        row("Sidebar Mode", config.sidebarMode.configValue)
        row("Tab Bar Mode", config.tabBarMode.configValue)
        row("Hide Tab Bar When Single Tab", config.hideTabBarWhenSingleTab ? "Yes" : "No")
      }

      if !config.popups.isEmpty {
        Section("Popups") {
          ForEach(config.popups, id: \.name) { popup in
            VStack(alignment: .leading, spacing: 2) {
              Text(popup.name).fontWeight(.medium)
              Text(popup.command)
                .foregroundStyle(.secondary)
                .font(.caption)
              if let shortcut = popup.shortcut {
                Text(shortcut)
                  .foregroundStyle(.secondary)
                  .font(.caption)
              }
            }
            .padding(.vertical, 2)
          }
        }
      }

      if config.ssh.defaultCommand != "ssh" || !config.ssh.hosts.isEmpty {
        Section("SSH") {
          row("Default Command", config.ssh.defaultCommand)
          ForEach(config.ssh.hosts, id: \.command) { host in
            if let hostname = host.hostname {
              row("Host", "\(hostname) → \(host.command)")
            } else if let regex = host.regex {
              row("Pattern", "\(regex) → \(host.command)")
            }
          }
        }
      }

      // TODO: add a GUI config editor with format-preserving TOML round-trip
      Section {
        HStack {
          Text(MyttyConfig.configFileURL.path)
            .foregroundStyle(.secondary)
            .font(.caption)
            .textSelection(.enabled)
          Spacer()
          Button("Open Config File") {
            NSWorkspace.shared.open(MyttyConfig.configFileURL)
          }
        }
      } header: {
        Text("Configuration File")
      } footer: {
        Text("Font, color, and terminal settings are loaded from Ghostty config at launch. Override in ~/.config/mytty/ghostty.conf.")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
    }
    .formStyle(.grouped)
    .frame(width: 500, height: 500)
    .padding()
  }

  private func row(_ label: String, _ value: String) -> some View {
    LabeledContent(label) {
      Text(value)
        .foregroundStyle(.secondary)
    }
  }
}
