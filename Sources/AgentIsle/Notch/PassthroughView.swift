import AppKit

/// Content view that only claims mouse events inside `interactiveRect`; clicks
/// anywhere else fall through to whatever window is behind (menu bar, other apps).
///
/// This is what stops the island's window from hijacking the whole top of the screen.
final class PassthroughView: NSView {
    /// The clickable region, in this view's (bottom-left origin) coordinates.
    var interactiveRect: NSRect = .zero
    /// Local: the island's exact silhouette inside `interactiveRect`, same coordinates.
    /// nil means the whole rect counts.
    var interactivePath: CGPath?

    /// Whether `point` (this view's coordinates) is over the island. A pointer pushed
    /// against the top of the screen reports exactly the top edge, which half-open
    /// containment excludes — so the top edge, and a hair past it, count as inside.
    func claims(_ point: NSPoint) -> Bool {
        guard point.y <= interactiveRect.maxY + 2 else { return false }
        let p = NSPoint(x: point.x, y: min(point.y, interactiveRect.maxY - 0.5))
        guard interactiveRect.contains(p) else { return false }
        return interactivePath?.contains(p) ?? true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard claims(point) else { return nil }
        return super.hitTest(point)
    }
}
