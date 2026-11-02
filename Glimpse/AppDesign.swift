import SwiftUI

enum AppDesign {

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    // MARK: - Corner Radius

    enum CornerRadius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 10
        static let xl: CGFloat = 16
    }

    // MARK: - Animation

    enum Animation {
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.2)
        static let quick = SwiftUI.Animation.easeOut(duration: 0.1)
    }

    // MARK: - Icon

    enum Icon {
        static let menuBarSize: CGFloat = 18
        static let accentLineWidth: CGFloat = 12
        static let accentLineHeight: CGFloat = 1.5
    }

    enum Control {
        static let iconTargetSize: CGFloat = 28
        static let dismissTargetSize: CGFloat = 24

        @MainActor
        static var iconTrailingClearance: CGFloat {
            max(0, NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) - Spacing.md)
        }
    }

    // MARK: - Calendar Grid

    enum Grid {
        static let cellHeight: CGFloat = 30
        static let weekNumberWidth: CGFloat = 28
        static let todayCircleSize: CGFloat = 28
        static let borderOpacity: Double = 0.25
        static let monthBorderOpacity: Double = 0.4
        static let workdayTintOpacity: Double = 0.08
        static let dimmedTextOpacity: Double = 0.4
        static let hoverBorderOpacity: Double = 0.4
    }

    // MARK: - Status Item

    enum StatusItem {
        static let height: CGFloat = 30
        static let padding: CGFloat = 6
        static let innerPadding: CGFloat = 4
        static let separatorInset: CGFloat = 4
        static let borderCornerRadius: CGFloat = 5
        static let borderWidth: CGFloat = 1
        static let borderOpacity: CGFloat = 0.3
        static let fontSize: CGFloat = 12
    }

    // MARK: - Colors

    enum Colors {
        static let accentRed = Color(nsColor: NSColor(red: 0.91, green: 0.25, blue: 0.25, alpha: 1.0))
        static let accentRedNS = NSColor(red: 0.91, green: 0.25, blue: 0.25, alpha: 1.0)

        static let menuBarText = NSColor.labelColor
        static let menuBarBorder = NSColor.secondaryLabelColor
        static let menuBarSeparator = NSColor.secondaryLabelColor
    }

    // MARK: - Caret

    enum Caret {
        static let width: CGFloat = 20
        static let tipRadius: CGFloat = 3
    }
}
