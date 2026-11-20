import AppKit
import GlimpseCore

/// Renders the complete menu bar status item — pill border, optional filled
/// background, date icon, separators, date text and the optional next-meeting
/// segment — into a single NSImage.
///
/// This image is set as the status button's `image` (`.imageOnly`). We do NOT
/// add a custom NSView subview to the status button: on macOS 26 the scene-managed
/// status-bar button never settles a child view's content frame, driving a
/// perpetual redraw loop (~40% CPU while idle). Compositing everything into the
/// button's own image uses only documented API and keeps the app at 0% idle.
///
/// The preferences preview (`StatusItemPreview`) renders the same image, so the
/// preview and the real menu bar cannot visually drift.
enum MenuBarItemRenderer {

    /// Resolved colors for one rendering (captured as immutable values by the draw closure).
    struct Palette {
        let content: NSColor
        let border: NSColor
        let background: NSColor?

        static func resolve(filled: Bool, imminent: Bool, isDark: Bool) -> Palette {
            let darkContent = NSColor(white: 0.1, alpha: 1.0)
            if imminent {
                return Palette(content: darkContent, border: darkContent,
                               background: AppDesign.Colors.accentAmberNS)
            }
            return Palette(
                content: filled ? darkContent : (isDark ? .white : darkContent),
                border: filled
                    ? darkContent
                    : (isDark ? NSColor(white: 1.0, alpha: 0.3) : NSColor(white: 0.0, alpha: 0.2)),
                background: filled
                    ? (isDark ? NSColor(white: 0.85, alpha: 1.0) : NSColor(white: 0.92, alpha: 1.0))
                    : nil
            )
        }
    }

    /// Produce the menu bar item image for the given options and appearance.
    /// - Parameters:
    ///   - options: display options (icon/date fields, filled background).
    ///   - dateString: the already-formatted date text (may be empty).
    ///   - meeting: the next-meeting segment, or nil when off/none.
    ///   - isDark: whether the destination appearance is dark.
    static func render(
        options: MenuBarDisplayOptions,
        dateString: String,
        meeting: MenuBarMeetingSegment? = nil,
        isDark: Bool
    ) -> NSImage {
        let height = NSStatusBar.system.thickness
        let palette = Palette.resolve(
            filled: options.showFilledBackground, imminent: meeting?.isImminent == true, isDark: isDark
        )
        let segments = textSegments(dateString: dateString, meeting: meeting, color: palette.content)
        let showIcon = options.showIcon || segments.isEmpty
        let width = itemWidth(showIcon: showIcon, segmentWidths: segments.map { ceil($0.size().width) })

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            drawPill(in: rect, palette: palette)
            var x = AppDesign.StatusItem.padding
            if showIcon {
                let iconSize = AppDesign.Icon.menuBarSize
                DateIconRenderer.render(textColor: palette.content)
                    .draw(in: NSRect(x: x, y: (height - iconSize) / 2, width: iconSize, height: iconSize))
                x += iconSize
            }
            for (index, segment) in segments.enumerated() {
                if showIcon || index > 0 {
                    x = drawSeparator(at: x, height: height, color: palette.content)
                }
                let size = segment.size()
                segment.draw(at: NSPoint(x: x, y: (height - size.height) / 2))
                x += ceil(size.width)
            }
            return true
        }

        // Non-template so the menu bar preserves our explicit colors instead of tinting.
        image.isTemplate = false
        return image
    }

    /// Date text, then the meeting text with tabular digits so the countdown doesn't jitter.
    private static func textSegments(
        dateString: String, meeting: MenuBarMeetingSegment?, color: NSColor
    ) -> [NSAttributedString] {
        let fontSize = AppDesign.StatusItem.fontSize
        var segments: [NSAttributedString] = []
        if !dateString.isEmpty {
            segments.append(NSAttributedString(string: dateString, attributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .medium), .foregroundColor: color,
            ]))
        }
        if let meeting, !meeting.text.isEmpty {
            segments.append(NSAttributedString(string: meeting.text, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium),
                .foregroundColor: color,
            ]))
        }
        return segments
    }

    /// Padding, optional icon, one separator (1pt + inner padding each side) before
    /// every text segment that follows something, and the text widths.
    static func itemWidth(showIcon: Bool, segmentWidths: [CGFloat]) -> CGFloat {
        let separator = AppDesign.StatusItem.innerPadding * 2 + 1
        let separators = CGFloat(max(0, segmentWidths.count - (showIcon ? 0 : 1)))
        return ceil(AppDesign.StatusItem.padding * 2
            + (showIcon ? AppDesign.Icon.menuBarSize : 0)
            + separators * separator
            + segmentWidths.reduce(0, +))
    }

    private static func drawPill(in rect: NSRect, palette: Palette) {
        let corner = AppDesign.StatusItem.borderCornerRadius
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: corner, yRadius: corner)
        if let background = palette.background {
            background.setFill()
            path.fill()
        }
        palette.border.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private static func drawSeparator(at x: CGFloat, height: CGFloat, color: NSColor) -> CGFloat {
        let inner = AppDesign.StatusItem.innerPadding
        let inset = AppDesign.StatusItem.separatorInset
        color.setFill()
        NSRect(x: x + inner, y: inset, width: 1, height: height - inset * 2).fill()
        return x + inner + 1 + inner
    }
}
