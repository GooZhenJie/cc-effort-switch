@preconcurrency import AppKit
import ApplicationServices

enum PointerShield {
    static let barrierMarker: Int64 = 0x43434542

    static func moveAway(in application: String) -> Bool {
        guard let process = NSRunningApplication.runningApplications(withBundleIdentifier: application).first,
              let corner = windowCorner(of: process.processIdentifier),
              let event = mouseMoved(to: corner) else { return false }
        event.setIntegerValueField(.eventSourceUserData, value: ActionRunner.marker)
        event.postToPid(process.processIdentifier)
        return true
    }

    static func postBarrier() {
        guard let location = CGEvent(source: nil)?.location, let event = mouseMoved(to: location) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: barrierMarker)
        event.post(tap: .cghidEventTap)
    }

    private static func windowCorner(of pid: pid_t) -> CGPoint? {
        let root = AXUIElementCreateApplication(pid)
        guard let window: AXUIElement = MenuReader.attribute(root, kAXFocusedWindowAttribute),
              let value: AXValue = MenuReader.attribute(window, kAXPositionAttribute) else { return nil }
        var origin = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &origin) else { return nil }
        return CGPoint(x: origin.x + 4, y: origin.y + 4)
    }

    private static func mouseMoved(to point: CGPoint) -> CGEvent? {
        CGEvent(
            mouseEventSource: CGEventSource(stateID: .privateState),
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left)
    }
}
