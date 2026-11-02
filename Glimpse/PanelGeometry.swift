import Foundation

struct PanelPlacement: Equatable, Sendable {
    let frame: CGRect
    let caretXOffset: CGFloat
    let maximumHeight: CGFloat
}

enum PanelGeometry {
    static let panelWidth: CGFloat = 316
    static let contentWidth: CGFloat = 300
    static let caretHeight: CGFloat = 12
    static let gapBelowMenuBar: CGFloat = 6
    static let edgeMargin: CGFloat = 10
    static let caretInset: CGFloat = 16
    static let tolerance: CGFloat = 0.5

    static func placement(
        statusItemFrame: CGRect, visibleFrame: CGRect, desiredHeight: CGFloat
    ) -> PanelPlacement? {
        guard validRect(statusItemFrame), validRect(visibleFrame),
              desiredHeight.isFinite, desiredHeight > 0,
              visibleFrame.width >= panelWidth + 2 * edgeMargin
        else { return nil }

        let left = visibleFrame.minX + edgeMargin
        let right = visibleFrame.maxX - panelWidth - edgeMargin
        let centeredX = round(statusItemFrame.midX - panelWidth / 2)
        let top = min(statusItemFrame.minY - gapBelowMenuBar, visibleFrame.maxY)
        let bottom = visibleFrame.minY + edgeMargin
        let maximumHeight = top - bottom
        let minimumHeight = caretHeight + 1
        guard left.isFinite, right.isFinite, left <= right, centeredX.isFinite,
              top.isFinite, bottom.isFinite, maximumHeight.isFinite,
              maximumHeight >= minimumHeight
        else { return nil }

        let height = max(minimumHeight, min(desiredHeight, maximumHeight))
        let x = max(left, min(centeredX, right))
        let frame = CGRect(x: x, y: top - height, width: panelWidth, height: height)
        let caretOffset = statusItemFrame.midX - x
        guard validRect(frame), caretOffset.isFinite else { return nil }

        return PanelPlacement(
            frame: frame,
            caretXOffset: max(caretInset, min(caretOffset, panelWidth - caretInset)),
            maximumHeight: maximumHeight
        )
    }

    static func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < tolerance
            && abs(lhs.origin.y - rhs.origin.y) < tolerance
            && abs(lhs.size.width - rhs.size.width) < tolerance
            && abs(lhs.size.height - rhs.size.height) < tolerance
    }

    private static func validRect(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite
            // CGRect's width/height getters normalize negative sizes.
            && rect.size.width.isFinite && rect.size.width > 0
            && rect.size.height.isFinite && rect.size.height > 0
            && rect.maxX.isFinite && rect.maxY.isFinite
            && rect.midX.isFinite && rect.midY.isFinite
    }
}
