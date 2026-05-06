import SwiftUI

@MainActor @Observable
final class ChromeFrameStore {
  var frames: [String: CGRect] = [:]
}

struct ChromeFrameReporter: ViewModifier {
  let key: String
  @Environment(ChromeFrameStore.self) private var frameStore

  func body(content: Content) -> some View {
    content.background {
      GeometryReader { geo in
        let frame = geo.frame(in: .global)
        Color.clear
          .onAppear { frameStore.frames[key] = frame }
          .onDisappear { frameStore.frames.removeValue(forKey: key) }
          .onChange(of: frame) { _, newFrame in
            frameStore.frames[key] = newFrame
          }
      }
    }
  }
}

extension View {
  func chromeFrame(_ key: String) -> some View {
    modifier(ChromeFrameReporter(key: key))
  }
}
