import Testing
@testable import CcEffortSwitchCore

@Test func retriesQuicklyThenBacksOff() {
    let delays = (1...12).map(RetrySchedule.delay(afterFailure:))
    #expect(delays == [0.1, 0.2, 0.4, 0.8, 1, 2, 4, 8, 16, 30, 30, 30])
    #expect(RetrySchedule.delay(afterFailure: 1000) == 30)
}
