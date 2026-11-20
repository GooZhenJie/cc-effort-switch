public struct MenuLayout: Equatable, Sendable {
    public let items: [String]
    public let current: Int

    public init(items: [String], current: Int) {
        self.items = items
        self.current = current
    }

    public static func make(items: [String], current: Int?) -> MenuLayout? {
        guard let current, items.indices.contains(current) else { return nil }
        return MenuLayout(items: items, current: current)
    }
}

public struct MenuSession: Sendable {
    public let rule: Rule
    public let layout: MenuLayout?
    public private(set) var index: Int?
    public private(set) var moved = false
    public private(set) var refusedToSelect = false

    public init(rule: Rule, layout: MenuLayout?) {
        self.rule = rule
        self.layout = rule.skip.isEmpty ? nil : layout
        index = self.layout?.current
    }

    public var skipsItems: Bool { !rule.skip.isEmpty }

    public mutating func strokes(for action: MenuAction, highlighted: Int? = nil) -> [ResolvedStroke] {
        switch action {
        case .open:
            return rule.open
        case .cancel:
            return rule.cancel
        case .next, .previous:
            moved = true
            guard skipsItems else { return action == .next ? rule.next : rule.previous }
            guard let layout, let current = index,
                  let target = step(from: current, by: action == .next ? 1 : -1, in: layout.items)
            else { return [] }
            index = target
            return path(from: current, to: target, count: layout.items.count)
        case .select:
            guard moved else { return rule.cancel }
            guard skipsItems else { return rule.select }
            guard let layout, let target = index, !isSkipped(layout.items[target]) else {
                refusedToSelect = true
                return rule.cancel
            }
            let start = highlighted.flatMap { layout.items.indices.contains($0) ? $0 : nil } ?? target
            return path(from: start, to: target, count: layout.items.count) + rule.select
        }
    }

    func path(from start: Int, to target: Int, count: Int) -> [ResolvedStroke] {
        guard start != target else { return [] }
        let downward = (target - start + count) % count
        let upward = (start - target + count) % count
        let options: [(passedItems: Int, strokes: [ResolvedStroke])] = [
            (downward - 1, repeated(rule.next, downward)),
            (upward - 1, repeated(rule.previous, upward)),
            (target, rule.first + repeated(rule.next, target)),
        ]
        return options.min { $0.passedItems < $1.passedItems }!.strokes
    }

    private func repeated(_ strokes: [ResolvedStroke], _ times: Int) -> [ResolvedStroke] {
        Array(repeating: strokes, count: times).flatMap { $0 }
    }

    private func step(from start: Int, by direction: Int, in items: [String]) -> Int? {
        var position = start
        for _ in 0..<items.count {
            position = (position + direction + items.count) % items.count
            if !isSkipped(items[position]) { return position }
        }
        return nil
    }

    func isSkipped(_ item: String) -> Bool {
        rule.skips(item)
    }
}
