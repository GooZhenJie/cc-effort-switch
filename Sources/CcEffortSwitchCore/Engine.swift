public enum InputEvent: Equatable, Sendable {
    case keyDown(keyCode: UInt16, modifiers: ModifierSet, isRepeat: Bool)
    case keyUp(keyCode: UInt16)
    case flagsChanged(modifiers: ModifierSet)
    case mouseDown
}

public enum Disposition: Equatable, Sendable {
    case pass
    case swallow
}

public enum MenuAction: Equatable, Sendable {
    case open
    case next
    case previous
    case select
    case cancel
}

public struct ScheduledAction: Equatable, Sendable {
    public let action: MenuAction
    public let notBefore: Double
    public let rule: Rule
}

public struct Reaction: Equatable, Sendable {
    public let disposition: Disposition
    public let actions: [ScheduledAction]

    static let pass = Reaction(disposition: .pass, actions: [])
    static let swallow = Reaction(disposition: .swallow, actions: [])
}

public final class Engine {
    private enum State: Equatable {
        case idle
        case active(ruleIndex: Int, openedAt: Double)
    }

    public private(set) var rules: [Rule]
    private var state: State = .idle
    private var swallowedKeyUps: Set<UInt16> = []
    private var lastScheduled: Double = 0

    public init(rules: [Rule]) {
        self.rules = rules
    }

    public var isActive: Bool { state != .idle }

    public func replaceRules(_ newRules: [Rule]) {
        rules = newRules
        state = .idle
    }

    public func handle(_ event: InputEvent, frontmostApplication: String?, now: Double) -> Reaction {
        if case .keyUp(let keyCode) = event {
            return swallowedKeyUps.remove(keyCode) != nil ? .swallow : .pass
        }
        if case .active(let ruleIndex, _) = state, rules[ruleIndex].application != frontmostApplication {
            state = .idle
        }
        switch state {
        case .idle:
            return handleIdle(event, frontmostApplication: frontmostApplication, now: now)
        case .active(let ruleIndex, let openedAt):
            return handleActive(event, rule: rules[ruleIndex], openedAt: openedAt, now: now)
        }
    }

    private func handleIdle(_ event: InputEvent, frontmostApplication: String?, now: Double) -> Reaction {
        guard case .keyDown(let keyCode, let modifiers, let isRepeat) = event, !isRepeat else { return .pass }
        guard let ruleIndex = rules.firstIndex(where: {
            $0.application == frontmostApplication && $0.keyCode == keyCode && $0.hold == modifiers
        }) else { return .pass }
        let rule = rules[ruleIndex]
        state = .active(ruleIndex: ruleIndex, openedAt: now)
        swallowedKeyUps.insert(keyCode)
        let open = schedule(.open, at: now, rule: rule)
        let next = schedule(.next, at: now + rule.openDelay, rule: rule)
        return Reaction(disposition: .swallow, actions: [open, next])
    }

    private func handleActive(_ event: InputEvent, rule: Rule, openedAt: Double, now: Double) -> Reaction {
        switch event {
        case .keyDown(let keyCode, let modifiers, let isRepeat):
            let movesBackward = modifiers == rule.hold.union(.shift) && !rule.hold.contains(.shift)
            let isTrigger = keyCode == rule.keyCode && (modifiers == rule.hold || movesBackward)
            let isArrow = (keyCode == KeyNames.down || keyCode == KeyNames.up) && modifiers.isSuperset(of: rule.hold)
            if isTrigger || isArrow {
                swallowedKeyUps.insert(keyCode)
                if isRepeat { return .swallow }
                let backward = isArrow ? keyCode == KeyNames.up : movesBackward
                let action = schedule(backward ? .previous : .next, at: max(now, openedAt + rule.openDelay), rule: rule)
                return Reaction(disposition: .swallow, actions: [action])
            }
            if keyCode == KeyNames.escape {
                state = .idle
                swallowedKeyUps.insert(keyCode)
                return Reaction(disposition: .swallow, actions: [schedule(.cancel, at: now, rule: rule)])
            }
            state = .idle
            return .pass
        case .flagsChanged(let modifiers):
            guard !modifiers.isSuperset(of: rule.hold) else { return .pass }
            state = .idle
            let earliest = max(now, openedAt + rule.openDelay) + rule.selectDelay
            return Reaction(disposition: .pass, actions: [schedule(.select, at: earliest, rule: rule)])
        case .mouseDown:
            state = .idle
            return .pass
        case .keyUp:
            return .pass
        }
    }

    private func schedule(_ action: MenuAction, at requested: Double, rule: Rule) -> ScheduledAction {
        let notBefore = max(requested, lastScheduled)
        lastScheduled = notBefore
        return ScheduledAction(action: action, notBefore: notBefore, rule: rule)
    }
}
