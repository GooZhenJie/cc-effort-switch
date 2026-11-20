public struct ModifierSet: OptionSet, Hashable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue & ModifierSet.allMask
    }

    public static let shift = ModifierSet(rawValue: 0x20000)
    public static let control = ModifierSet(rawValue: 0x40000)
    public static let option = ModifierSet(rawValue: 0x80000)
    public static let command = ModifierSet(rawValue: 0x100000)

    static let allMask: UInt64 = 0x20000 | 0x40000 | 0x80000 | 0x100000

    public init(eventFlags: UInt64) {
        self.init(rawValue: eventFlags)
    }

    public init(names: [String]) throws(ConfigurationError) {
        var set: ModifierSet = []
        for name in names {
            switch name.lowercased() {
            case "command", "cmd": set.insert(.command)
            case "shift": set.insert(.shift)
            case "option", "alt": set.insert(.option)
            case "control", "ctrl": set.insert(.control)
            default: throw .unknownModifier(name)
            }
        }
        self = set
    }
}

public enum KeyNames {
    public static let codes: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, "`": 50,
        "return": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "home": 115, "pageup": 116, "forwarddelete": 117, "end": 119, "pagedown": 121,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]

    public static let escape: UInt16 = 53
    public static let down: UInt16 = 125
    public static let up: UInt16 = 126

    public static func code(for name: String) throws(ConfigurationError) -> UInt16 {
        guard let code = codes[name.lowercased()] else { throw .unknownKey(name) }
        return code
    }
}
