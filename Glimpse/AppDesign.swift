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
        static let todayTargetWidth: CGFloat = 48
        static let todayBackgroundOpacity: Double = 0.10
        static let dismissTargetSize: CGFloat = 24
        static let focusLineWidth: CGFloat = 2
        static let aboutFocusLineWidth: CGFloat = 1
        static let focusInset: CGFloat = 2
        static let focusCornerRadius: CGFloat = 4

        @MainActor
        static var iconTrailingClearance: CGFloat {
            max(0, NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) - Spacing.md)
        }
    }

    enum Settings {
        static let contentSize = CGSize(width: 480, height: 490)
        /// The page is never shorter than its content (fit() still clamps to tiny screens),
        /// because SwiftUI Tab routing skips rows fully clipped by the scroll view.
        static let minimumContentSize = CGSize(width: 440, height: 490)
        static let contentInset: CGFloat = 20
        static let labelFontSize: CGFloat = 13
        static let supportingFontSize: CGFloat = 11.5
        static let labelColumnWidth: CGFloat = 132
        static let columnSpacing: CGFloat = 10
        static let classicRowSpacing: CGFloat = 9
        static let classicSectionInset: CGFloat = 12
        static let groupBorderWidth: CGFloat = 1
        static let rowSpacing: CGFloat = 10
        static let statusSpacing: CGFloat = 4
        static let minimumRowHeight: CGFloat = 22
        /// Focus reveal keeps at least this much row (label + control) visible, plus Spacing.sm.
        static let revealRowHeight: CGFloat = 28
        static let recorderWidth: CGFloat = 88
        static let workdayMinimumWidth: CGFloat = 32
        static let workdaySpacing: CGFloat = 3
        static let checkboxSpacing: CGFloat = 12
        static let layoutTolerance: CGFloat = 0.5
        static let screenInset: CGFloat = 10
        static let windowGap: CGFloat = 12
        static let linkSpacing: CGFloat = 14
        static let previewBaselineOffset: CGFloat = 4.5
    }

    enum Footer {
        static let height: CGFloat = 30
        static let iconSize: CGFloat = 13
        static let iconSpacing: CGFloat = 2
        static let contextSize: CGFloat = 11.5
        static let leadingInset: CGFloat = 14
        static let trailingInset: CGFloat = 6
        static let dividerHeight: CGFloat = 16
        static let confirmationInset: CGFloat = 12
        static let hoverBackgroundOpacity: Double = 0.08
        static let pressedBackgroundOpacity: Double = 0.14
        static let pinnedBackgroundOpacity: Double = 0.14

        @MainActor
        static var scrollbarClearance: CGFloat {
            NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        }
    }

    // MARK: - Calendar Grid

    enum Grid {
        static let cellHeight: CGFloat = 30
        static let weekNumberWidth: CGFloat = 28
        static let todayCircleSize: CGFloat = 28
        static let borderOpacity: Double = 0.25
        static let outerBorderOpacity: Double = 0.12
        static let monthBorderOpacity: Double = 0.4
        static let workdayTintOpacity: Double = 0.04
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
        static func settingsSurface(in environment: EnvironmentValues) -> Color {
            environment.colorScheme == .dark
                ? Color(red: 36 / 255, green: 36 / 255, blue: 38 / 255)
                : Color(red: 247 / 255, green: 247 / 255, blue: 248 / 255)
        }

        static func settingsGroup(in environment: EnvironmentValues) -> Color {
            environment.colorScheme == .dark
                ? Color(red: 48 / 255, green: 48 / 255, blue: 50 / 255)
                : .white
        }

        static let calendarSurface = Color(nsColor: .windowBackgroundColor)
        static let calendarContextText = Color.primary.opacity(0.80)
        static let accentRed = Color(nsColor: NSColor(red: 0.91, green: 0.25, blue: 0.25, alpha: 1.0))
        static let accentRedNS = NSColor(red: 0.91, green: 0.25, blue: 0.25, alpha: 1.0)

        /// Bounds opaque calendar fills for white labels using the current resolved hue.
        static func calendarSolidFill(_ color: Color, in environment: EnvironmentValues) -> Color {
            let resolved = color.resolve(in: environment)
            var red = Double(resolved.linearRed)
            var green = Double(resolved.linearGreen)
            var blue = Double(resolved.linearBlue)
            let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            let minimumLuminance = 0.170
            let maximumLuminance = 0.175

            if luminance > maximumLuminance {
                let scale = maximumLuminance / luminance
                red *= scale
                green *= scale
                blue *= scale
            } else if luminance < minimumLuminance {
                let whiteMix = (minimumLuminance - luminance) / (1 - luminance)
                red += (1 - red) * whiteMix
                green += (1 - green) * whiteMix
                blue += (1 - blue) * whiteMix
            } else {
                return color
            }
            return Color(.sRGBLinear, red: red, green: green, blue: blue, opacity: 1)
        }

        /// Functional marks keep native dark accents and bound their light-appearance luminance.
        static func calendarEssentialAccent(in environment: EnvironmentValues) -> Color {
            guard environment.colorScheme == .light else { return .accentColor }
            return calendarSolidFill(.accentColor, in: environment)
        }

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
