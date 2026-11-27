@preconcurrency import AppKit
import CcEffortSwitchCore
import os

@MainActor
final class EventTap {
    private let engine: Engine
    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var awaitingBarrierSince: Double?
    private var ignoredPointerEvents = 0
    private static let pointerTypes: Set<CGEventType> = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
    private static let barrierTimeout: Double = 2
    private static let log = Logger(subsystem: "io.github.goozhenjie.cc-effort-switch", category: "pointer")

    init(engine: Engine) {
        self.engine = engine
    }

    var isRunning: Bool { machPort != nil }

    func start() -> Bool {
        guard machPort == nil else { return true }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
            + Array(Self.pointerTypes)
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        machPort = port
        runLoopSource = source
        return true
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let machPort { CGEvent.tapEnable(tap: machPort, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let sourceData = event.getIntegerValueField(.eventSourceUserData)
        if sourceData == PointerShield.barrierMarker {
            if let since = awaitingBarrierSince {
                let waited = Int((ProcessInfo.processInfo.systemUptime - since) * 1000)
                Self.log.notice("barrier returned waited=\(waited)ms ignored=\(self.ignoredPointerEvents)")
            }
            awaitingBarrierSince = nil
            ignoredPointerEvents = 0
            return Unmanaged.passUnretained(event)
        }
        if sourceData == ActionRunner.marker {
            return Unmanaged.passUnretained(event)
        }
        let now = ProcessInfo.processInfo.systemUptime
        if Self.pointerTypes.contains(type) {
            guard ignoresPointer(at: now) else { return Unmanaged.passUnretained(event) }
            ignoredPointerEvents += 1
            return nil
        }
        let input: InputEvent
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = ModifierSet(eventFlags: event.flags.rawValue)
        switch type {
        case .keyDown:
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            input = .keyDown(keyCode: keyCode, modifiers: modifiers, isRepeat: isRepeat)
        case .keyUp:
            input = .keyUp(keyCode: keyCode)
        case .flagsChanged:
            input = .flagsChanged(modifiers: modifiers)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            input = .mouseDown
        default:
            return Unmanaged.passUnretained(event)
        }
        let reaction = engine.handle(
            input,
            frontmostApplication: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            now: now)
        if reaction.actions.contains(where: { $0.action == .select || $0.action == .cancel }) {
            awaitingBarrierSince = now
        }
        for action in reaction.actions {
            ActionRunner.run(action)
        }
        return reaction.disposition == .swallow ? nil : Unmanaged.passUnretained(event)
    }

    private func ignoresPointer(at now: Double) -> Bool {
        if engine.isActive { return true }
        guard let since = awaitingBarrierSince else { return false }
        if now - since < Self.barrierTimeout { return true }
        Self.log.notice("barrier timed out ignored=\(self.ignoredPointerEvents)")
        awaitingBarrierSince = nil
        ignoredPointerEvents = 0
        return false
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
    return MainActor.assumeIsolated {
        tap.handle(type: type, event: event)
    }
}
