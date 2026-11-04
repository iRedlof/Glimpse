import AppKit
import SwiftUI
import Testing
@testable import Glimpse

struct AppDesignTests {

    // MARK: - Spacing

    @Test
    func spacing_valuesArePositive() {
        #expect(AppDesign.Spacing.xs > 0)
        #expect(AppDesign.Spacing.sm > 0)
        #expect(AppDesign.Spacing.md > 0)
        #expect(AppDesign.Spacing.lg > 0)
        #expect(AppDesign.Spacing.xl > 0)
    }

    @Test
    func spacing_ascendingOrder() {
        #expect(AppDesign.Spacing.xs < AppDesign.Spacing.sm)
        #expect(AppDesign.Spacing.sm < AppDesign.Spacing.md)
        #expect(AppDesign.Spacing.md < AppDesign.Spacing.lg)
        #expect(AppDesign.Spacing.lg < AppDesign.Spacing.xl)
    }

    // MARK: - Corner Radius

    @Test
    func cornerRadius_valuesArePositive() {
        #expect(AppDesign.CornerRadius.sm > 0)
        #expect(AppDesign.CornerRadius.md > 0)
        #expect(AppDesign.CornerRadius.lg > 0)
        #expect(AppDesign.CornerRadius.xl > 0)
    }

    // MARK: - Grid

    @Test
    func grid_cellHeightIsReasonable() {
        #expect(AppDesign.Grid.cellHeight >= 20)
        #expect(AppDesign.Grid.cellHeight <= 50)
    }

    @Test
    func grid_todayCircleFitsCellHeight() {
        #expect(AppDesign.Grid.todayCircleSize <= AppDesign.Grid.cellHeight)
    }

    @Test
    func grid_opacityValuesInRange() {
        #expect(AppDesign.Grid.borderOpacity > 0)
        #expect(AppDesign.Grid.borderOpacity <= 1)
        #expect(AppDesign.Grid.monthBorderOpacity > 0)
        #expect(AppDesign.Grid.monthBorderOpacity <= 1)
    }

    // MARK: - Status Item

    @Test
    func statusItem_heightIsReasonable() {
        #expect(AppDesign.StatusItem.height >= 22)
        #expect(AppDesign.StatusItem.height <= 40)
    }

    // MARK: - Icon

    @Test
    func icon_menuBarSizeIsStandard() {
        #expect(AppDesign.Icon.menuBarSize == 18)
    }

    // MARK: - Caret

    @Test
    func caret_widthIsReasonable() {
        #expect(AppDesign.Caret.width > 10)
        #expect(AppDesign.Caret.width < 40)
    }

    @Test
    func caret_tipRadiusIsSmall() {
        #expect(AppDesign.Caret.tipRadius > 0)
        #expect(AppDesign.Caret.tipRadius < AppDesign.Caret.width / 2)
    }

    // MARK: - Calendar Fill

    @Test(arguments: [
        Color.black, .white,
        .red, .green, .blue, .yellow, .orange, .purple, .pink,
        Color(.sRGB, red: 0.45, green: 0.45, blue: 0.45, opacity: 1),
        .accentColor, AppDesign.Colors.accentRed
    ], [false, true])
    @MainActor
    func calendarSolidFill_supportsWhiteLabelsAndSurfaceSeparation(input: Color, dark: Bool) throws {
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))

        // Color.Resolved supplies linear channels, so WCAG needs no second transfer conversion.
        func relativeLuminance(_ color: Color.Resolved) -> Double {
            0.2126 * Double(color.linearRed)
                + 0.7152 * Double(color.linearGreen)
                + 0.0722 * Double(color.linearBlue)
        }

        func contrastRatio(_ first: Double, _ second: Double) -> Double {
            (max(first, second) + 0.05) / (min(first, second) + 0.05)
        }

        appearance.performAsCurrentDrawingAppearance {
            var environment = EnvironmentValues()
            environment.colorScheme = dark ? .dark : .light
            let fill = AppDesign.Colors.calendarSolidFill(input, in: environment).resolve(in: environment)
            let surface = AppDesign.Colors.calendarSurface.resolve(in: environment)
            let white = Color.white.resolve(in: environment)
            let resolvedInput = input.resolve(in: environment)
            let inputChannels = [resolvedInput.linearRed, resolvedInput.linearGreen, resolvedInput.linearBlue]
            let outputChannels = [fill.linearRed, fill.linearGreen, fill.linearBlue]
            var separatedPairs = 0
            // Ignore near-neutral differences; retain meaningful chromatic order above rounding noise.
            for (first, second) in [(0, 1), (0, 2), (1, 2)] {
                let inputDifference = inputChannels[first] - inputChannels[second]
                if abs(inputDifference) > 0.1 {
                    separatedPairs += 1
                    let outputDifference = outputChannels[first] - outputChannels[second]
                    #expect(inputDifference * outputDifference > 0)
                    #expect(abs(outputDifference) > 0.01)
                }
            }
            let chromaticSamples: [Color] = [.red, .green, .blue, .yellow, .orange, .purple, .pink,
                                            AppDesign.Colors.accentRed]
            if chromaticSamples.contains(input) {
                #expect(separatedPairs > 0, "Chromatic samples must exercise a separated channel pair")
            }

            #expect([fill.linearRed, fill.linearGreen, fill.linearBlue].allSatisfy {
                $0.isFinite && (0...1).contains($0)
            })
            #expect(fill.opacity.isFinite && fill.opacity == 1)
            let fillLuminance = relativeLuminance(fill)
            #expect(contrastRatio(relativeLuminance(white), fillLuminance) >= 4.5)
            #expect(contrastRatio(fillLuminance, relativeLuminance(surface)) >= 3.0)
        }
    }

    @Test(arguments: [false, true])
    @MainActor
    func calendarEssentialAccent_separatesLightMarksAndRetainsDarkAccent(dark: Bool) throws {
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))

        func luminance(_ color: Color.Resolved) -> Double {
            0.2126 * Double(color.linearRed)
                + 0.7152 * Double(color.linearGreen)
                + 0.0722 * Double(color.linearBlue)
        }

        func contrast(_ first: Double, _ second: Double) -> Double {
            (max(first, second) + 0.05) / (min(first, second) + 0.05)
        }

        appearance.performAsCurrentDrawingAppearance {
            var environment = EnvironmentValues()
            environment.colorScheme = dark ? .dark : .light
            let accent = AppDesign.Colors.calendarEssentialAccent(in: environment).resolve(in: environment)
            let rawAccent = Color.accentColor.resolve(in: environment)
            let channels = [accent.linearRed, accent.linearGreen, accent.linearBlue, accent.opacity]
            #expect(channels.allSatisfy { $0.isFinite && (0...1).contains($0) })
            if dark {
                #expect(channels == [rawAccent.linearRed, rawAccent.linearGreen,
                                     rawAccent.linearBlue, rawAccent.opacity])
            } else {
                let surface = AppDesign.Colors.calendarSurface.resolve(in: environment)
                let pinTint = Color.accentColor.opacity(AppDesign.Footer.pinnedBackgroundOpacity)
                    .resolve(in: environment)
                // Composite the resolved raw tint over the actual calendar surface in linear light.
                let pinSurfaceLuminance = luminance(pinTint) * Double(pinTint.opacity)
                    + luminance(surface) * (1 - Double(pinTint.opacity))
                #expect(accent.opacity == 1)
                #expect(contrast(luminance(accent), luminance(surface)) >= 3)
                #expect(contrast(luminance(accent), pinSurfaceLuminance) >= 3)
            }
        }
    }
}
