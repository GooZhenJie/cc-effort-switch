import Testing
@testable import CcEffortSwitchCore

private let fiveLevels = ["Low", "Medium", "High", "Extra", "Max", "Ultracode"]
private let fourLevels = ["Low", "Medium", "High", "Max"]
private let home = ResolvedStroke(keyCode: KeyNames.codes["home"]!, modifiers: [])
private let down = ResolvedStroke(keyCode: KeyNames.down, modifiers: [])
private let up = ResolvedStroke(keyCode: KeyNames.up, modifiers: [])
private let enter = ResolvedStroke(keyCode: KeyNames.codes["return"]!, modifiers: [])
private let escape = ResolvedStroke(keyCode: KeyNames.escape, modifiers: [])

private func session(_ items: [String], current: Int) throws -> MenuSession {
    MenuSession(rule: try defaultRule(), layout: MenuLayout(items: items, current: current))
}

@Test func neighboursTakeOneKey() throws {
    var menu = try session(fiveLevels, current: 1)
    #expect(menu.strokes(for: .next) == [down])
    #expect(menu.strokes(for: .next) == [down])
    #expect(menu.strokes(for: .previous) == [up])
}

@Test func movingDownFromMaxJumpsHomeOverUltracode() throws {
    var menu = try session(fiveLevels, current: 4)
    #expect(menu.strokes(for: .next) == [home])
    #expect(menu.index == 0)
}

@Test func movingUpFromLowPassesUltracodeWithoutStopping() throws {
    var menu = try session(fiveLevels, current: 0)
    #expect(menu.strokes(for: .previous) == [up, up])
    #expect(menu.index == 4)
}

@Test func movingFromUltracodeLeavesIt() throws {
    var menu = try session(fiveLevels, current: 5)
    #expect(menu.strokes(for: .next) == [down])
    var upward = try session(fiveLevels, current: 5)
    #expect(upward.strokes(for: .previous) == [up])
}

@Test func menusWithoutUltracodeWrapWithOneKey() throws {
    var menu = try session(fourLevels, current: 3)
    #expect(menu.strokes(for: .next) == [down])
    #expect(menu.strokes(for: .previous) == [up])
}

@Test func steppingThroughEveryLevelNeverLandsOnUltracode() throws {
    var menu = try session(fiveLevels, current: 2)
    var visited: [Int] = []
    for _ in 0..<10 {
        _ = menu.strokes(for: .next)
        visited.append(menu.index!)
    }
    #expect(visited == [3, 4, 0, 1, 2, 3, 4, 0, 1, 2])
}

@Test func selectWhenHighlightMatchesPressesReturnOnly() throws {
    var menu = try session(fiveLevels, current: 1)
    _ = menu.strokes(for: .next)
    #expect(menu.strokes(for: .select, highlighted: 2) == [enter])
}

@Test func selectMovesBackWhenMouseMovedTheHighlight() throws {
    var menu = try session(fiveLevels, current: 1)
    _ = menu.strokes(for: .next)
    #expect(menu.strokes(for: .select, highlighted: 5) == [down, down, down, enter])
    var other = try session(fiveLevels, current: 1)
    _ = other.strokes(for: .next)
    #expect(other.strokes(for: .select, highlighted: 3) == [up, enter])
}

@Test func selectWithoutKnownHighlightTrustsTrackedPosition() throws {
    var menu = try session(fiveLevels, current: 1)
    _ = menu.strokes(for: .next)
    #expect(menu.strokes(for: .select, highlighted: nil) == [enter])
    #expect(!menu.refusedToSelect)
}

@Test func releasingWithoutMovingCancels() throws {
    var menu = try session(fiveLevels, current: 2)
    #expect(menu.strokes(for: .select) == [escape])
    #expect(!menu.refusedToSelect)
}

@Test func unreadableMenuNeverSelects() throws {
    var menu = MenuSession(rule: try defaultRule(), layout: nil)
    #expect(menu.strokes(for: .next).isEmpty)
    #expect(menu.strokes(for: .select) == [escape])
    #expect(menu.refusedToSelect)
}

@Test func withoutSkipMovesRelatively() throws {
    var definition = try JSONDecoderHelper.defaultDefinition()
    definition.skip = []
    let rule = try Rule(definition: definition)
    var menu = MenuSession(rule: rule, layout: MenuLayout(items: fiveLevels, current: 4))
    #expect(menu.layout == nil)
    #expect(menu.strokes(for: .next) == [down])
    #expect(menu.strokes(for: .previous) == [up])
    #expect(menu.strokes(for: .select) == [enter])
}

@Test func skipMatchesNameFollowedByDescription() throws {
    let menu = try session(["Low Quick replies", "Ultracode Dynamic workflows"], current: 0)
    #expect(menu.isSkipped("Ultracode Dynamic workflows"))
    #expect(!menu.isSkipped("Ultracoder"))
}

@Test func layoutNeedsAKnownCurrentItem() {
    #expect(MenuLayout.make(items: fiveLevels, current: 3)?.current == 3)
    #expect(MenuLayout.make(items: fiveLevels, current: nil) == nil)
    #expect(MenuLayout.make(items: fiveLevels, current: 6) == nil)
}

@Test func realClaudeTitlesAreHandled() throws {
    let titles = ["Low", "Medium Recommended", "High", "Extra", "Max 3.5× or more usage", "Ultracode"]
    var menu = try session(titles, current: 4)
    #expect(menu.strokes(for: .next) == [home])
    #expect(menu.strokes(for: .previous) == [up, up])
}
