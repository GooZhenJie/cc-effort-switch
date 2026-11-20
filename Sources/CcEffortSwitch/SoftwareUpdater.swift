import AppKit
import Sparkle

@MainActor
final class SoftwareUpdater: NSObject, SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController?
    private(set) var hasWaitingUpdate = false

    static var isConfigured: Bool {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        return !(key ?? "").isEmpty && !(feed ?? "").isEmpty
    }

    func start() {
        guard Self.isConfigured else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    var isAvailable: Bool { controller != nil }

    var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? false }

    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        if immediateFocus { return true }
        MainActor.assumeIsolated { hasWaitingUpdate = true }
        return false
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { hasWaitingUpdate = false }
    }
}
