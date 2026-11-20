import Testing
@testable import CcEffortSwitchCore

@Test func levelIsTheLastWordOfTheModelTitle() {
    #expect(EffortIndicator.level(fromTitle: "Model: Opus 5.5 Extra") == 3)
    #expect(EffortIndicator.level(fromTitle: "Model: Opus 5.5 low") == 0)
    #expect(EffortIndicator.level(fromTitle: "Model: Sonnet 5.5 Ultracode") == 5)
}

@Test func textAfterTheLevelIsIgnored() {
    #expect(EffortIndicator.level(fromTitle: "Model: Opus 5.5 Max 3.5× or more usage") == 4)
    #expect(EffortIndicator.level(fromTitle: "Model: Opus 5.5 Medium Recommended") == 1)
    #expect(EffortIndicator.level(fromTitle: "Model: Opus 5.5 Extra Uses more than High") == 3)
}

@Test func unknownTitlesHaveNoLevel() {
    #expect(EffortIndicator.level(fromTitle: "Model: Opus 5.5") == nil)
    #expect(EffortIndicator.level(fromTitle: "Effort Extra") == nil)
    #expect(EffortIndicator.level(fromTitle: "") == nil)
}

@Test func skippedLevelsComeFromTheClaudeRule() throws {
    #expect(EffortIndicator.skippedLevels(in: [try defaultRule()]) == [5])
    #expect(EffortIndicator.skippedLevels(in: []) == [])
}
