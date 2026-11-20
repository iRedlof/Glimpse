import AppKit

enum DateIconRenderer {
    /// - Parameter day: the day of month to draw. Captured up front (not read from the
    ///   clock inside the draw handler) so a cached image always matches its key.
    static func render(
        day: Int = Calendar.current.component(.day, from: Date()),
        textColor: NSColor = .labelColor
    ) -> NSImage {
        let iconSize = AppDesign.Icon.menuBarSize
        let size = NSSize(width: iconSize, height: iconSize)
        let image = NSImage(size: size, flipped: false) { rect in
            let dayString = "\(day)"

            let fontSize: CGFloat = day < 10 ? 12 : 11
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: textColor,
            ]

            let textSize = dayString.size(withAttributes: attributes)
            let textOrigin = NSPoint(
                x: (rect.width - textSize.width) / 2,
                y: (rect.height - textSize.height) / 2 + 1
            )
            dayString.draw(at: textOrigin, withAttributes: attributes)

            let lineWidth = AppDesign.Icon.accentLineWidth
            let lineHeight = AppDesign.Icon.accentLineHeight
            let lineX = (rect.width - lineWidth) / 2
            let linePath = NSBezierPath(
                roundedRect: NSRect(
                    x: lineX, y: 2,
                    width: lineWidth, height: lineHeight
                ),
                xRadius: lineHeight / 2,
                yRadius: lineHeight / 2
            )
            AppDesign.Colors.accentRedNS.setFill()
            linePath.fill()

            return true
        }

        image.isTemplate = false
        return image
    }
}
