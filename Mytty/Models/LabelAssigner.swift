enum LabelAssigner {
  @MainActor
  static func assignLabels(
    targets: [any HintTarget],
    alphabet: String
  ) -> [HintLabel] {
    var seen = Set<Character>()
    let chars = alphabet.filter { seen.insert($0).inserted }
    guard chars.count >= 2, !targets.isEmpty else { return [] }

    let maxSingle = chars.count
    let maxDouble = chars.count * chars.count

    if targets.count <= maxSingle {
      return zip(targets.prefix(maxSingle), chars).map { target, char in
        HintLabel(target: target, label: String(char))
      }
    }

    let capped = Array(targets.prefix(maxDouble))
    var result: [HintLabel] = []
    result.reserveCapacity(capped.count)
    var index = 0
    for first in chars {
      for second in chars {
        guard index < capped.count else { return result }
        result.append(HintLabel(target: capped[index], label: "\(first)\(second)"))
        index += 1
      }
    }
    return result
  }
}
