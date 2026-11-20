import AppKit
import ApplicationServices
import CcEffortSwitchCore
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let engine = Engine(rules: [])
    private lazy var eventTap = EventTap(engine: engine)
    private let updater = SoftwareUpdater()
    private var statusItem: NSStatusItem?
    private var permissionTimer: Timer?
    private var configurationWatcher: ConfigurationWatcher?
    private var configurationProblem: String?
    private var menuProblem: String?
    private var effortLevel: Int?
    private lazy var effortMonitor = EffortMonitor { [weak self] level in
        self?.effortLevel = level
        self?.updateStatusImage()
    }

    static let configurationURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/cc-effort-switch/config.jsonc")
    static let previousConfigurationURL = configurationURL.deletingPathExtension().appendingPathExtension("json")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        updateStatusImage()
        ActionRunner.onProblem = { [weak self] problem in
            self?.menuProblem = problem
        }
        loadConfiguration()
        let watcher = ConfigurationWatcher(fileURL: Self.configurationURL) { [weak self] in
            self?.loadConfiguration()
        }
        watcher.start()
        configurationWatcher = watcher
        updater.start()
        startWhenTrusted(prompt: true)
    }

    private func startWhenTrusted(prompt: Bool) {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        if AXIsProcessTrustedWithOptions(options), eventTap.start() {
            effortMonitor.start()
            permissionTimer?.invalidate()
            permissionTimer = nil
            return
        }
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated {
                self.startWhenTrusted(prompt: false)
            }
        }
    }

    private func loadConfiguration() {
        let url = Self.configurationURL
        do {
            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: url.path), fileManager.fileExists(atPath: Self.previousConfigurationURL.path) {
                try fileManager.moveItem(at: Self.previousConfigurationURL, to: url)
            }
            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try ConfigurationLoader.defaultFileContents.write(to: url, atomically: true, encoding: .utf8)
            }
            let data = try Data(contentsOf: url)
            engine.replaceRules(try ConfigurationLoader.rules(from: data))
            configurationProblem = nil
            updateStatusImage()
        } catch let error as ConfigurationError {
            configurationProblem = error.description
        } catch {
            configurationProblem = error.localizedDescription
        }
    }

    private func updateStatusImage() {
        let skipped = EffortIndicator.skippedLevels(in: engine.rules)
        statusItem?.button?.image = EffortIcon.image(level: effortLevel, skipped: skipped)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status: String
        if let configurationProblem {
            status = configurationProblem
        } else if !eventTap.isRunning {
            status = "Needs Accessibility permission"
        } else if let menuProblem {
            status = menuProblem
        } else {
            let count = engine.rules.count
            status = count == 1 ? "1 rule active" : "\(count) rules active"
        }
        let statusLine = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        if !eventTap.isRunning {
            menu.addItem(item("Open Accessibility Settings", #selector(openAccessibilitySettings)))
        }
        menu.addItem(item("Open Config File", #selector(openConfigurationFile)))
        let launchAtLogin = item("Launch at Login", #selector(toggleLaunchAtLogin))
        launchAtLogin.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchAtLogin)
        if updater.isAvailable {
            menu.addItem(.separator())
            let check = item(updater.hasWaitingUpdate ? "Update Available…" : "Check for Updates…", #selector(checkForUpdates))
            check.isEnabled = updater.canCheckForUpdates
            menu.addItem(check)
            let automatic = item("Check for Updates Automatically", #selector(toggleAutomaticUpdates))
            automatic.state = updater.automaticallyChecksForUpdates ? .on : .off
            menu.addItem(automatic)
        }
        menu.addItem(.separator())
        menu.addItem(item("Quit CcEffortSwitch", #selector(NSApplication.terminate(_:)), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = action == #selector(NSApplication.terminate(_:)) ? NSApp : self
        return menuItem
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openConfigurationFile() {
        loadConfiguration()
        let workspace = NSWorkspace.shared
        let editor = workspace.urlForApplication(toOpen: Self.configurationURL)
            ?? workspace.urlForApplication(toOpen: .json)
            ?? workspace.urlForApplication(withBundleIdentifier: "com.apple.TextEdit")
        guard let editor else {
            workspace.open(Self.configurationURL)
            return
        }
        workspace.open([Self.configurationURL], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func checkForUpdates() {
        updater.checkForUpdates()
    }

    @objc private func toggleAutomaticUpdates() {
        updater.automaticallyChecksForUpdates.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}
