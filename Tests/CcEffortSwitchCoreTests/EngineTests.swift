import Foundation
import Testing
@testable import CcEffortSwitchCore

private let claude = "com.anthropic.claudefordesktop"
private let other = "com.apple.Safari"
private let keyE = KeyNames.codes["e"]!

func defaultRule() throws -> Rule {
    try ConfigurationLoader.rules(from: Data(ConfigurationLoader.defaultFileContents.utf8))[0]
}

private func makeEngine() throws -> Engine {
    Engine(rules: [try defaultRule()])
}

private func press(_ engine: Engine, _ keyCode: UInt16, _ modifiers: ModifierSet, app: String = claude, at now: Double, isRepeat: Bool = false) -> Reaction {
    engine.handle(.keyDown(keyCode: keyCode, modifiers: modifiers, isRepeat: isRepeat), frontmostApplication: app, now: now)
}

private func flags(_ engine: Engine, _ modifiers: ModifierSet, app: String = claude, at now: Double) -> Reaction {
    engine.handle(.flagsChanged(modifiers: modifiers), frontmostApplication: app, now: now)
}

private func kinds(_ reaction: Reaction) -> [MenuAction] {
    reaction.actions.map(\.action)
}

@Test func firstPressOpensMenuAndMovesDown() throws {
    let engine = try makeEngine()
    let reaction = press(engine, keyE, .command, at: 10)
    let rule = try defaultRule()
    #expect(reaction.disposition == .swallow)
    #expect(reaction.actions == [
        ScheduledAction(action: .open, notBefore: 10, rule: rule),
        ScheduledAction(action: .next, notBefore: 10.1, rule: rule),
    ])
}

@Test func otherApplicationsAreLeftAlone() throws {
    let engine = try makeEngine()
    #expect(press(engine, keyE, .command, app: other, at: 10) == Reaction(disposition: .pass, actions: []))
    #expect(flags(engine, [], app: other, at: 11).actions.isEmpty)
}

@Test func nativeShortcutPassesWhenIdle() throws {
    let engine = try makeEngine()
    #expect(press(engine, keyE, [.command, .shift], at: 10).disposition == .pass)
}

@Test func tappingAgainMovesDownAfterMenuOpens() throws {
    let engine = try makeEngine()
    _ = press(engine, keyE, .command, at: 10)
    let reaction = press(engine, keyE, .command, at: 10.02)
    #expect(reaction.disposition == .swallow)
    #expect(kinds(reaction) == [.next])
    #expect(reaction.actions.first?.notBefore == 10.1)
}

@Test func shiftMovesUp() throws {
    let engine = try makeEngine()
    _ = press(engine, keyE, .command, at: 10)
    #expect(kinds(press(engine, keyE, [.command, .shift], at: 11)) == [.previous])
}

@Test func arrowsWithCommandStillMove() throws {
    let engine = try makeEngine()
    _ = press(engine, keyE, .command, at: 10)
    let fnAndKeypadFlags: UInt64 = 0x800000 | 0x200000
    let arrowModifiers = ModifierSet(eventFlags: ModifierSet.command.rawValue | fnAndKeypadFlags)
    #expect(kinds(press(engine, KeyNames.down, arrowModifiers, at: 11)) == [.next])
    #expect(kinds(press(engine, KeyNames.up, arrowModifiers, at: 12)) == [.previous])
}

@Test func releasingCommandSelects() throws {
    let engine = try makeEngine()
    _ = press(engine, keyE, .command, at: 10)
    _ = press(engine, keyE, .command, at: 11)
    let reaction = flags(engine, [], at: 12)
    #expect(reaction.disposition == .pass)
    #expect(kinds(reaction) == [.select])
    #expect(reaction.actions.first?.notBefore == 12.1)
    #expect(!engine.isActive)
}

@Test func quickTapWaitsForMenuBeforeSelecting() throws {
    let engine = try makeEngine()
    _ = press(engine, keyE, .command, at: 10)
    #expect(flags(engine, [], at: 10.01).actions.first?.notBefore == 10.2)
}

@Test func releasingShiftKeepsMenuOpen() throws {
    let engine = try makeEngine()
    _ = press(engine, keyE, .command, at: 10)
    _ = flags(engine, [.command, .shift], at: 11)
    #expect(flags(engine, .command, at: 12).actions.isEmpty)
    #expect(engine.isActive)
}

@Test func escapeCancels() throws {
    let engine = try makeEngine()
    _ = press(engine, keyE, .command, at: 10)
    let reaction = press(engine, KeyNames.escape, .command, at: 11)
    #expect(reaction.disposition == .swallow)
    #expect(kinds(reaction) == [.cancel])
    #expect(flags(engine, [], at: 12).actions.isEmpty)
}

@Test func mouseClickEndsWithoutSelecting() throws {
    let engine = try makeEngine()
    _ = press(engine, keyE, .command, at: 10)
    #expect(engine.handle(.mouseDown, frontmostApplication: claude, now: 11).disposition == .pass)
    #expect(flags(engine, [], at: 12).actions.isEmpty)
}

@Test func otherKeyEndsWithoutSelecting() throws {
    let engine = try makeEngine()
    _ = press(engine, keyE, .command, at: 10)
    #expect(press(engine, KeyNames.codes["a"]!, .command, at: 11).disposition == .pass)
    #expect(flags(engine, [], at: 12).actions.isEmpty)
}

@Test func switchingApplicationsEndsWithoutSelecting() throws {
    let engine = try makeEngine()
    _ = press(engine, keyE, .command, at: 10)
    #expect(flags(engine, [], app: other, at: 12).actions.isEmpty)
    #expect(!engine.isActive)
}

@Test func autorepeatDoesNotMove() throws {
    let engine = try makeEngine()
    _ = press(engine, keyE, .command, at: 10)
    #expect(press(engine, keyE, .command, at: 10.5, isRepeat: true) == Reaction(disposition: .swallow, actions: []))
}

@Test func triggerKeyUpIsSwallowedOnce() throws {
    let engine = try makeEngine()
    _ = press(engine, keyE, .command, at: 10)
    #expect(engine.handle(.keyUp(keyCode: keyE), frontmostApplication: claude, now: 10.1).disposition == .swallow)
    #expect(engine.handle(.keyUp(keyCode: keyE), frontmostApplication: claude, now: 10.2).disposition == .pass)
    #expect(engine.handle(.keyUp(keyCode: KeyNames.codes["a"]!), frontmostApplication: claude, now: 10.3).disposition == .pass)
}

@Test func actionsNeverRunOutOfOrder() throws {
    let engine = try makeEngine()
    var times: [Double] = []
    times += press(engine, keyE, .command, at: 10).actions.map(\.notBefore)
    times += press(engine, keyE, .command, at: 10.01).actions.map(\.notBefore)
    times += press(engine, keyE, [.command, .shift], at: 10.02).actions.map(\.notBefore)
    times += press(engine, keyE, .command, at: 10.3).actions.map(\.notBefore)
    times += flags(engine, [], at: 10.31).actions.map(\.notBefore)
    #expect(times == times.sorted())
    #expect(times.count == 6)
}

@Test func secondSessionStartsAfterFirstEnds() throws {
    let engine = try makeEngine()
    _ = press(engine, keyE, .command, at: 10)
    _ = flags(engine, [], at: 11)
    #expect(kinds(press(engine, keyE, .command, at: 20)) == [.open, .next])
}
