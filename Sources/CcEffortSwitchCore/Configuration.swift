import Foundation

public enum ConfigurationError: Error, Equatable, CustomStringConvertible {
    case unknownKey(String)
    case unknownModifier(String)
    case emptyHold(rule: String)
    case emptyActions(rule: String, action: String)
    case missingFirst(rule: String)
    case unreadable(String)

    public var description: String {
        switch self {
        case .unknownKey(let name): "Unknown key \"\(name)\""
        case .unknownModifier(let name): "Unknown modifier \"\(name)\""
        case .emptyHold(let rule): "Rule \"\(rule)\" needs at least one modifier in \"hold\""
        case .emptyActions(let rule, let action): "Rule \"\(rule)\" needs at least one key in \"\(action)\""
        case .missingFirst(let rule): "Rule \"\(rule)\" needs \"first\" to skip items"
        case .unreadable(let reason): reason
        }
    }
}

public struct KeyStroke: Codable, Equatable, Sendable {
    public var key: String
    public var modifiers: [String]?

    public init(key: String, modifiers: [String]? = nil) {
        self.key = key
        self.modifiers = modifiers
    }
}

public struct RuleDefinition: Codable, Equatable, Sendable {
    public var name: String
    public var application: String
    public var hold: [String]
    public var key: String
    public var open: [KeyStroke]
    public var next: [KeyStroke]
    public var previous: [KeyStroke]
    public var select: [KeyStroke]
    public var cancel: [KeyStroke]
    public var first: [KeyStroke]?
    public var skip: [String]?
    public var menuTitle: String?
    public var openDelayMilliseconds: Int?
    public var selectDelayMilliseconds: Int?
}

public struct ConfigurationFile: Codable, Equatable, Sendable {
    public var rules: [RuleDefinition]
}

public struct ResolvedStroke: Equatable, Hashable, Sendable {
    public let keyCode: UInt16
    public let modifiers: ModifierSet

    public init(keyCode: UInt16, modifiers: ModifierSet) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public struct Rule: Equatable, Sendable {
    public let name: String
    public let application: String
    public let hold: ModifierSet
    public let keyCode: UInt16
    public let open: [ResolvedStroke]
    public let next: [ResolvedStroke]
    public let previous: [ResolvedStroke]
    public let select: [ResolvedStroke]
    public let cancel: [ResolvedStroke]
    public let first: [ResolvedStroke]
    public let skip: [String]
    public let menuTitle: String?
    public let openDelay: Double
    public let selectDelay: Double

    public static let defaultDelayMilliseconds = 100

    public init(definition: RuleDefinition) throws(ConfigurationError) {
        func resolve(_ strokes: [KeyStroke], _ action: String) throws(ConfigurationError) -> [ResolvedStroke] {
            guard !strokes.isEmpty else { throw .emptyActions(rule: definition.name, action: action) }
            var resolved: [ResolvedStroke] = []
            for stroke in strokes {
                resolved.append(ResolvedStroke(
                    keyCode: try KeyNames.code(for: stroke.key),
                    modifiers: try ModifierSet(names: stroke.modifiers ?? [])))
            }
            return resolved
        }
        name = definition.name
        application = definition.application
        hold = try ModifierSet(names: definition.hold)
        guard !hold.isEmpty else { throw .emptyHold(rule: definition.name) }
        keyCode = try KeyNames.code(for: definition.key)
        open = try resolve(definition.open, "open")
        next = try resolve(definition.next, "next")
        previous = try resolve(definition.previous, "previous")
        select = try resolve(definition.select, "select")
        cancel = try resolve(definition.cancel, "cancel")
        skip = definition.skip ?? []
        if skip.isEmpty, (definition.first ?? []).isEmpty {
            first = []
        } else {
            guard let firstStrokes = definition.first, !firstStrokes.isEmpty else { throw .missingFirst(rule: definition.name) }
            first = try resolve(firstStrokes, "first")
        }
        menuTitle = definition.menuTitle
        openDelay = Double(definition.openDelayMilliseconds ?? Rule.defaultDelayMilliseconds) / 1000
        selectDelay = Double(definition.selectDelayMilliseconds ?? Rule.defaultDelayMilliseconds) / 1000
    }
}

public enum ConfigurationLoader {
    public static func rules(from data: Data) throws(ConfigurationError) -> [Rule] {
        let file: ConfigurationFile
        do {
            let decoder = JSONDecoder()
            decoder.allowsJSON5 = true
            file = try decoder.decode(ConfigurationFile.self, from: data)
        } catch {
            throw .unreadable("Config file is not valid: \(error.localizedDescription)")
        }
        var rules: [Rule] = []
        for definition in file.rules {
            rules.append(try Rule(definition: definition))
        }
        return rules
    }

    public static let defaultFileContents = """
    // CcEffortSwitch settings. Changes take effect when this file is saved.
    //
    // Key names: a to z, 0 to 9, punctuation such as "," or "/", "return", "escape",
    // "tab", "space", "delete", "forwarddelete", "up", "down", "left", "right",
    // "home", "end", "pageup", "pagedown", "f1" to "f12". Keys are matched by their
    // position on a US keyboard.
    // Modifier names: "command", "shift", "option", "control".
    {
      "rules": [
        {
          // The name of this rule. Error messages in the menu bar use it to say
          // which rule has a problem.
          "name": "Claude effort",

          // Bundle identifier of the app this rule works in.
          // Run `osascript -e 'id of app "Claude"'` to find it for another app.
          "application": "com.anthropic.claudefordesktop",

          // The shortcut: hold these modifiers and press "key" to open the menu
          // and move to the next item. Press "key" again to keep moving down,
          // or add Shift to move up.
          // Release the modifiers to select. Esc closes the menu without selecting.
          // To use Option-E instead of Command-E, change "hold" to ["option"].
          "hold": ["command"],
          "key": "e",

          // Keys sent to the app. "open" is Claude's own shortcut for the Effort
          // menu, so it doesn't change when you change the shortcut above.
          "open": [{ "key": "e", "modifiers": ["command", "shift"] }],
          "next": [{ "key": "down" }],
          "previous": [{ "key": "up" }],
          "select": [{ "key": "return" }],
          "cancel": [{ "key": "escape" }],

          // Keys that jump to the first item in the menu. Needed when "skip" is used.
          "first": [{ "key": "home" }],

          // Items that are never selected. Remove "Ultracode" to allow it.
          // To skip more, add their names, such as ["Ultracode", "Max"].
          "skip": ["Ultracode"],

          // Start of the menu's title, so items are read from the right menu.
          // In Claude, the Effort menu sits inside the model menu.
          "menuTitle": "Effort"
        }
      ]
    }

    """
}

extension Rule {
    public func skips(_ item: String) -> Bool {
        let name = item.lowercased()
        return skip.contains { entry in
            let skipped = entry.lowercased()
            return name == skipped || name.hasPrefix(skipped + " ")
        }
    }
}
