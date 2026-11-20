public enum EffortIndicator {
    public static let application = "com.anthropic.claudefordesktop"
    public static let titlePrefix = "Model:"
    public static let levels = ["Low", "Medium", "High", "Extra", "Max", "Ultracode"]

    public static func level(fromTitle title: String) -> Int? {
        guard title.hasPrefix(titlePrefix) else { return nil }
        for word in title.dropFirst(titlePrefix.count).split(whereSeparator: \.isWhitespace) {
            if let index = levels.firstIndex(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) {
                return index
            }
        }
        return nil
    }

    public static func skippedLevels(in rules: [Rule]) -> Set<Int> {
        let skipping = rules.filter { $0.application == application }
        return Set(levels.indices.filter { index in skipping.contains { $0.skips(levels[index]) } })
    }
}
