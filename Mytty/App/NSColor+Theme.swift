import AppKit

extension NSColor {
  var luminance: CGFloat {
    guard let rgb = usingColorSpace(.sRGB) else { return 0 }
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
    return (0.299 * r) + (0.587 * g) + (0.114 * b)
  }

  var isLightColor: Bool {
    luminance > 0.5
  }

  func darken(by amount: CGFloat) -> NSColor {
    var h: CGFloat = 0
    var s: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    return NSColor(
      hue: h,
      saturation: s,
      brightness: min(b * (1 - amount), 1),
      alpha: a
    )
  }
}
