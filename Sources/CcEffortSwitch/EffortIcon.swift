import AppKit
import CcEffortSwitchCore

enum EffortIcon {
    private static let bounds = NSRect(x: 136, y: 170, width: 752, height: 870)
    private static let widths: [CGFloat] = [520, 460, 400, 340, 280, 440]
    private static let height: CGFloat = 16

    static func image(level: Int?, skipped: Set<Int>) -> NSImage {
        let scale = height / bounds.height
        let image = NSImage(size: NSSize(width: bounds.width * scale, height: height), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -bounds.minX, y: -bounds.minY)
            for row in EffortIndicator.levels.indices {
                let center = 230 + CGFloat(row) * 150
                let isCurrent = row == level
                NSColor.black.withAlphaComponent(skipped.contains(row) && !isCurrent ? 0.35 : 1).setFill()
                let rect = isCurrent
                    ? NSRect(x: 140, y: center - 55, width: 744, height: 110)
                    : NSRect(x: 200, y: center - 18, width: widths[row], height: 36)
                let radius: CGFloat = isCurrent ? 40 : 18
                NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            }
            return true
        }
        image.isTemplate = true
        let name = level.map { EffortIndicator.levels[$0] }
        image.accessibilityDescription = name.map { "CcEffortSwitch, effort \($0)" } ?? "CcEffortSwitch"
        return image
    }
}
