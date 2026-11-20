import Foundation
import Testing
@testable import CcEffortSwitchCore

private func definition(hold: [String] = ["command"], key: String = "e", next: [KeyStroke] = [KeyStroke(key: "down")]) -> RuleDefinition {
    RuleDefinition(
        name: "Test", application: "com.example.app", hold: hold, key: key,
        open: [KeyStroke(key: "e", modifiers: ["command", "shift"])],
        next: next, previous: [KeyStroke(key: "up")],
        select: [KeyStroke(key: "return")], cancel: [KeyStroke(key: "escape")],
        first: nil, skip: nil, menuTitle: nil,
        openDelayMilliseconds: nil, selectDelayMilliseconds: 250)
}

@Test func defaultFileParses() throws {
    let rules = try ConfigurationLoader.rules(from: Data(ConfigurationLoader.defaultFileContents.utf8))
    #expect(rules.count == 1)
    #expect(rules[0].hold == .command)
    #expect(rules[0].openDelay == 0.1)
    #expect(rules[0].selectDelay == 0.1)
}

@Test func customDelayIsRead() throws {
    #expect(try Rule(definition: definition()).selectDelay == 0.25)
}

@Test func unknownKeyIsReported() {
    #expect(throws: ConfigurationError.unknownKey("enter")) {
        try Rule(definition: definition(key: "enter"))
    }
}

@Test func unknownModifierIsReported() {
    #expect(throws: ConfigurationError.unknownModifier("hyper")) {
        try Rule(definition: definition(hold: ["hyper"]))
    }
}

@Test func holdNeedsAModifier() {
    #expect(throws: ConfigurationError.emptyHold(rule: "Test")) {
        try Rule(definition: definition(hold: []))
    }
}

@Test func actionsCannotBeEmpty() {
    #expect(throws: ConfigurationError.emptyActions(rule: "Test", action: "next")) {
        try Rule(definition: definition(next: []))
    }
}

@Test func invalidJsonIsReported() {
    #expect(throws: ConfigurationError.self) {
        try ConfigurationLoader.rules(from: Data("{".utf8))
    }
}

enum JSONDecoderHelper {
    static func defaultDefinition() throws -> RuleDefinition {
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        return try decoder.decode(ConfigurationFile.self, from: Data(ConfigurationLoader.defaultFileContents.utf8)).rules[0]
    }
}

@Test func defaultSkipsUltracode() throws {
    let rule = try defaultRule()
    #expect(rule.skip == ["Ultracode"])
    #expect(rule.first == [ResolvedStroke(keyCode: KeyNames.codes["home"]!, modifiers: [])])
    #expect(rule.menuTitle == "Effort")
}

@Test func skipNeedsFirst() throws {
    var definition = try JSONDecoderHelper.defaultDefinition()
    definition.first = nil
    #expect(throws: ConfigurationError.missingFirst(rule: "Claude effort")) {
        try Rule(definition: definition)
    }
}

@Test func commentsAreAllowed() throws {
    #expect(ConfigurationLoader.defaultFileContents.contains("// "))
    let rules = try ConfigurationLoader.rules(from: Data(ConfigurationLoader.defaultFileContents.utf8))
    #expect(rules.count == 1)
}

@Test func plainJsonStillLoads() throws {
    let plain = #"{"rules":[{"name":"A","application":"x","hold":["command"],"key":"e","open":[{"key":"e"}],"next":[{"key":"down"}],"previous":[{"key":"up"}],"select":[{"key":"return"}],"cancel":[{"key":"escape"}]}]}"#
    #expect(try ConfigurationLoader.rules(from: Data(plain.utf8)).count == 1)
}
