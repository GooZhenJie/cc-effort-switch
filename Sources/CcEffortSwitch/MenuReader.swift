@preconcurrency import AppKit
import ApplicationServices

struct MenuSnapshot {
    let items: [String]
    let current: Int?
    let highlighted: Int?
}

enum MenuReader {
    static let nodeLimit = 20000

    static func read(application: String, menuTitle: String?) -> MenuSnapshot? {
        guard let process = NSRunningApplication.runningApplications(withBundleIdentifier: application).first else { return nil }
        let root = AXUIElementCreateApplication(process.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.5)
        AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        guard let window: AXUIElement = attribute(root, kAXFocusedWindowAttribute) else { return nil }

        var candidates: [(element: AXUIElement, depth: Int)] = []
        var visited = 0
        func walk(_ element: AXUIElement, depth: Int) {
            visited += 1
            guard visited < nodeLimit else { return }
            let role: String? = attribute(element, kAXRoleAttribute)
            if role == kAXMenuItemRole { return }
            if let title: String = attribute(element, kAXTitleAttribute), !title.isEmpty, matches(title, menuTitle) {
                candidates.append((element, depth))
            }
            for child in children(of: element) {
                walk(child, depth: depth + 1)
            }
        }
        walk(window, depth: 0)

        for candidate in candidates.sorted(by: { $0.depth > $1.depth }) {
            let items = menuItems(in: candidate.element)
            guard items.count > 1 else { continue }
            let focused: AXUIElement? = attribute(root, kAXFocusedUIElementAttribute)
            let highlighted = items.firstIndex { item in focused.map { CFEqual($0, item) } ?? false }
            let current = items.firstIndex(where: isChecked) ?? highlighted
            return MenuSnapshot(items: items.map(name), current: current, highlighted: highlighted)
        }
        return nil
    }

    private static func matches(_ title: String, _ menuTitle: String?) -> Bool {
        guard let menuTitle else { return true }
        return title == menuTitle || title.hasPrefix(menuTitle + " ")
    }

    private static func menuItems(in container: AXUIElement) -> [AXUIElement] {
        var items: [AXUIElement] = []
        func walk(_ element: AXUIElement) {
            for child in children(of: element) {
                let role: String? = attribute(child, kAXRoleAttribute)
                if role == kAXMenuItemRole {
                    items.append(child)
                } else if (attribute(child, kAXTitleAttribute) as String?)?.isEmpty ?? true {
                    walk(child)
                }
            }
        }
        walk(container)
        return items
    }

    private static func isChecked(_ item: AXUIElement) -> Bool {
        if let mark: String = attribute(item, "AXMenuItemMarkChar"), !mark.isEmpty { return true }
        if let value: NSNumber = attribute(item, kAXValueAttribute), value.intValue == 1 { return true }
        return false
    }

    private static func name(of item: AXUIElement) -> String {
        (attribute(item, kAXTitleAttribute) as String?) ?? (attribute(item, kAXDescriptionAttribute) as String?) ?? ""
    }

    static func children(of element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute) as [AXUIElement]?) ?? []
    }

    static func attribute<Value>(_ element: AXUIElement, _ name: String) -> Value? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? Value
    }
}
