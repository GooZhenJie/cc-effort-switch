@preconcurrency import AppKit
import CcEffortSwitchCore
import os

enum ActionRunner {
    static let marker: Int64 = 0x43434553

    private static let queue = DispatchQueue(label: "cc-effort-switch.actions")
    private static let log = Logger(subsystem: "io.github.goozhenjie.cc-effort-switch", category: "menu")
    nonisolated(unsafe) private static var session: MenuSession?
    nonisolated(unsafe) static var onProblem: (@MainActor (String?) -> Void)?

    static func run(_ scheduled: ScheduledAction) {
        queue.async {
            let wait = scheduled.notBefore - ProcessInfo.processInfo.systemUptime
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            let endsSession = scheduled.action == .select || scheduled.action == .cancel
            defer { if endsSession { PointerShield.postBarrier() } }
            let frontmost = DispatchQueue.main.sync {
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            }
            guard frontmost == scheduled.rule.application else {
                session = nil
                return
            }
            if scheduled.action == .open {
                let movedAway = PointerShield.moveAway(in: scheduled.rule.application)
                log.notice("pointer moved away=\(movedAway)")
                post(scheduled.rule.open)
                session = MenuSession(rule: scheduled.rule, layout: scheduled.rule.skip.isEmpty ? nil : readLayout(for: scheduled.rule))
                report(session?.skipsItems == true && session?.layout == nil
                    ? "Couldn't read the menu for rule \"\(scheduled.rule.name)\", so nothing will be selected" : nil)
                return
            }
            guard var current = session, current.rule == scheduled.rule else { return }
            var highlighted: Int?
            if scheduled.action == .select, current.skipsItems, current.moved, current.layout != nil {
                highlighted = MenuReader.read(application: scheduled.rule.application, menuTitle: scheduled.rule.menuTitle)?.highlighted
            }
            let strokes = current.strokes(for: scheduled.action, highlighted: highlighted)
            post(strokes)
            log.notice("action=\(String(describing: scheduled.action), privacy: .public) index=\(current.index ?? -1) highlighted=\(highlighted ?? -1) keys=\(strokes.count) refused=\(current.refusedToSelect)")
            session = current
            if endsSession {
                session = nil
            }
        }
    }

    private static func readLayout(for rule: Rule) -> MenuLayout? {
        Thread.sleep(forTimeInterval: rule.openDelay)
        for attempt in 0..<10 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.05) }
            if let snapshot = MenuReader.read(application: rule.application, menuTitle: rule.menuTitle),
               let layout = MenuLayout.make(items: snapshot.items, current: snapshot.current) {
                log.notice("menu read attempt=\(attempt) items=\(layout.items.joined(separator: " / "), privacy: .public) current=\(layout.current)")
                return layout
            }
        }
        log.notice("menu unreadable rule=\(rule.name, privacy: .public)")
        return nil
    }

    private static func report(_ problem: String?) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { onProblem?(problem) }
        }
    }

    private static func post(_ strokes: [ResolvedStroke]) {
        let source = CGEventSource(stateID: .privateState)
        for stroke in strokes {
            for isDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: stroke.keyCode, keyDown: isDown) else { continue }
                event.flags = CGEventFlags(rawValue: stroke.modifiers.rawValue)
                event.setIntegerValueField(.eventSourceUserData, value: marker)
                event.post(tap: .cghidEventTap)
            }
        }
    }
}
