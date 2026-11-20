public enum RetrySchedule {
    static let shortRetryLimit = 4
    static let initialDelay = 0.1
    static let maximumShortDelay = 0.8
    static let initialSparseDelay = 1.0
    static let sparseCooldown = 30.0

    public static func delay(afterFailure failure: Int) -> Double {
        let failure = max(failure, 1)
        if failure <= shortRetryLimit {
            return min(maximumShortDelay, initialDelay * Double(1 << (failure - 1)))
        }
        let tier = min(failure - shortRetryLimit, 16)
        return min(sparseCooldown, initialSparseDelay * Double(1 << (tier - 1)))
    }
}
