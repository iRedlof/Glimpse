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
        static let focusInset: CGFloat = 2
        static let focusCornerRadius: CGFloat = 4

        @MainActor
        static var iconTrailingClearance: CGFloat {
            max(0, NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) - Spacing.md)
        }
    }

    enum Settings {
        static let contentSize = CGSize(width: 600, height: 600)
        static let minimumContentSize = CGSize(width: 520, height: 360)
        static let contentInset: CGFloat = 20
        static let sectionSpacing: CGFloat = 20
        static let headingSpacing: CGFloat = 8
        static let headingFontSize: CGFloat = 17
        static let labelFontSize: CGFloat = 13
        static let supportingFontSize: CGFloat = 12
        static let groupHorizontalInset: CGFloat = 12
        static let groupVerticalInset: CGFloat = 8
        static let groupCornerRadius: CGFloat = 8
        static let groupBorderWidth: CGFloat = 1
        static let increasedContrastBorderWidth: CGFloat = 2
        static let dividerInset: CGFloat = 4
        static let rowSpacing: CGFloat = 8
        static let statusSpacing: CGFloat = 4
        static let minimumRowHeight: CGFloat = 28
        static let previewHeight: CGFloat = 44
        static let recorderWidth: CGFloat = 196
        static let weekdayPickerWidth: CGFloat = 160
        static let providerPickerWidth: CGFloat = 160
        static let workdayMinimumWidth: CGFloat = 56
        static let checkboxSpacing: CGFloat = 8
        static let layoutTolerance: CGFloat = 0.5
        static let screenInset: CGFloat = 10
        static let windowGap: CGFloat = 12
    }

    enum Footer {
        static let pinTargetWidth: CGFloat = 64
        static let settingsTargetWidth: CGFloat = 84
        static let pinnedBackgroundOpacity: Double = 0.14
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
