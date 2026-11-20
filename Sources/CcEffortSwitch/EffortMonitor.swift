@preconcurrency import AppKit
import ApplicationServices
import CcEffortSwitchCore
import os

final class EffortMonitor: @unchecked Sendable {
    private let logger = Logger(subsystem: "io.github.goozhenjie.cc-effort-switch", category: "effort")
    private let onChange: @MainActor @Sendable (Int?) -> Void
    private var runLoop: CFRunLoop?
    private var process: pid_t = 0
    private var application: AXUIElement?
    private var observer: AXObserver?
    private var window: AXUIElement?
    private var buttons: [AXUIElement] = []
    private var level: Int?
    private var hasPublished = false
    private var lastUnrecognizedTitle: String?
    private var subscribed = false
    private var failures = 0
    private var retryTimer: CFRunLoopTimer?

    init(onChange: @escaping @MainActor @Sendable (Int?) -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard runLoop == nil else { return }
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            let current = CFRunLoopGetCurrent()
            let keepAlive = CFRunLoopTimerCreateWithHandler(nil, .greatestFiniteMagnitude, 0, 0, 0) { _ in }
            CFRunLoopAddTimer(current, keepAlive, .defaultMode)
            runLoop = current
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "EffortMonitor"
        thread.start()
        ready.wait()

        let center = NSWorkspace.shared.notificationCenter
        let names = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        for name in names {
            center.addObserver(forName: name, object: nil, queue: nil) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == EffortIndicator.application else { return }
                let terminated = name == NSWorkspace.didTerminateApplicationNotification
                self?.perform { monitor in
                    terminated ? monitor.detach() : monitor.attach()
                }
            }
        }
        perform { $0.attach() }
    }

    private func perform(_ work: @escaping @Sendable (EffortMonitor) -> Void) {
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [self] in work(self) }
        CFRunLoopWakeUp(runLoop)
    }

    private func attach() {
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: EffortIndicator.application)
            .first(where: { !$0.isTerminated }) else {
            detach()
            return
        }
        if running.processIdentifier == process, observer != nil {
            refresh(trigger: "activate")
            return
        }
        detach(publishing: false)
        process = running.processIdentifier
        let element = AXUIElementCreateApplication(process)
        AXUIElementSetMessagingTimeout(element, 0.5)
        application = element

        let callback: AXObserverCallback = { _, _, notification, refcon in
            guard let refcon else { return }
            Unmanaged<EffortMonitor>.fromOpaque(refcon).takeUnretainedValue().refresh(trigger: notification as String)
        }
        var created: AXObserver?
        if AXObserverCreate(process, callback, &created) == .success, let created, let runLoop {
            observer = created
            CFRunLoopAddSource(runLoop, AXObserverGetRunLoopSource(created), .defaultMode)
        }
        prepare(trigger: "launch")
    }

    private func prepare(trigger: String) {
        guard let application else { return }
        AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        if !subscribed, let observer {
            let results = [kAXFocusedUIElementChangedNotification, kAXFocusedWindowChangedNotification].map { name in
                AXObserverAddNotification(observer, application, name as CFString, refcon)
            }
            subscribed = results.allSatisfy { $0 == .success || $0 == .notificationAlreadyRegistered }
            if !subscribed {
                logger.debug("subscribe failed errors=\(results.map(\.rawValue))")
            }
        }
        refresh(trigger: trigger)
        if subscribed, !buttons.isEmpty {
            failures = 0
            cancelRetry()
        } else {
            failures += 1
            scheduleRetry(after: RetrySchedule.delay(afterFailure: failures))
        }
    }

    private func scheduleRetry(after delay: Double) {
        cancelRetry()
        guard let runLoop else { return }
        let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + delay, 0, 0, 0) { [weak self] _ in
            self?.retryTimer = nil
            self?.prepare(trigger: "retry")
        }
        retryTimer = timer
        CFRunLoopAddTimer(runLoop, timer, .defaultMode)
    }

    private func cancelRetry() {
        if let retryTimer {
            CFRunLoopTimerInvalidate(retryTimer)
        }
        retryTimer = nil
    }

    private var refcon: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }

    private func detach(publishing: Bool = true) {
        if let observer, let runLoop {
            CFRunLoopRemoveSource(runLoop, AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        cancelRetry()
        observer = nil
        subscribed = false
        failures = 0
        application = nil
        window = nil
        buttons = []
        process = 0
        if publishing { publish(nil, trigger: "quit") }
    }

    fileprivate func refresh(trigger: String) {
        guard let application else {
            publish(nil, trigger: trigger)
            return
        }
        let focusedWindow: AXUIElement? = MenuReader.attribute(application, kAXFocusedWindowAttribute)
        var titles = buttons.map(title)
        let windowChanged = !sameElement(focusedWindow, window)
        if windowChanged || titles.isEmpty || titles.contains(where: { $0 == nil }) {
            rescan(in: focusedWindow)
            titles = buttons.map(title)
        }
        let index = chosenButton(in: application)
        let title = index.flatMap { titles[$0] }
        let current = title.flatMap(EffortIndicator.level(fromTitle:))
        if current == nil, let title, title != lastUnrecognizedTitle {
            logger.info("unrecognized title=\(title, privacy: .public)")
        }
        lastUnrecognizedTitle = current == nil ? title : nil
        publish(current, trigger: trigger)
    }

    private func rescan(in focusedWindow: AXUIElement?) {
        if let observer {
            for button in buttons {
                AXObserverRemoveNotification(observer, button, kAXTitleChangedNotification as CFString)
                AXObserverRemoveNotification(observer, button, kAXUIElementDestroyedNotification as CFString)
            }
        }
        window = focusedWindow
        buttons = []
        guard let focusedWindow else { return }
        var stack = [focusedWindow]
        var visited = 0
        while let element = stack.popLast(), visited < MenuReader.nodeLimit {
            visited += 1
            let role: String? = MenuReader.attribute(element, kAXRoleAttribute)
            if role == kAXPopUpButtonRole, let title = title(element), title.hasPrefix(EffortIndicator.titlePrefix) {
                buttons.append(element)
                continue
            }
            stack.append(contentsOf: MenuReader.children(of: element))
        }
        if let observer {
            for button in buttons {
                AXObserverAddNotification(observer, button, kAXTitleChangedNotification as CFString, refcon)
                AXObserverAddNotification(observer, button, kAXUIElementDestroyedNotification as CFString, refcon)
            }
        }
    }

    private func chosenButton(in application: AXUIElement) -> Int? {
        guard buttons.count > 1 else { return buttons.isEmpty ? nil : 0 }
        guard let focused: AXUIElement = MenuReader.attribute(application, kAXFocusedUIElementAttribute),
              let target = center(of: focused) else { return 0 }
        let distances = buttons.map { button in
            center(of: button).map { hypot($0.x - target.x, $0.y - target.y) } ?? .infinity
        }
        return distances.indices.min { distances[$0] < distances[$1] }
    }

    private func center(of element: AXUIElement) -> CGPoint? {
        guard let positionValue: AXValue = MenuReader.attribute(element, kAXPositionAttribute),
              let sizeValue: AXValue = MenuReader.attribute(element, kAXSizeAttribute) else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position), AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }
        return CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
    }

    private func title(_ element: AXUIElement) -> String? {
        MenuReader.attribute(element, kAXTitleAttribute)
    }

    private func sameElement(_ first: AXUIElement?, _ second: AXUIElement?) -> Bool {
        switch (first, second) {
        case (nil, nil): true
        case let (first?, second?): CFEqual(first, second)
        default: false
        }
    }

    private func publish(_ newLevel: Int?, trigger: String) {
        guard !hasPublished || newLevel != level else { return }
        hasPublished = true
        level = newLevel
        let name = newLevel.map { EffortIndicator.levels[$0] } ?? "none"
        logger.info("effort=\(name, privacy: .public) trigger=\(trigger, privacy: .public) buttons=\(self.buttons.count)")
        let onChange = onChange
        DispatchQueue.main.async {
            MainActor.assumeIsolated { onChange(newLevel) }
        }
    }
}
