import AppKit
import Combine
import GlimpseCore
import SwiftUI
import Testing

@testable import Glimpse

@Suite(.serialized)
@MainActor
struct MenuBarItemRendererTests {

    private func opts(
        showIcon: Bool = true,
        showDayOfWeek: Bool = true,
        showFilledBackground: Bool = false
    ) -> MenuBarDisplayOptions {
        MenuBarDisplayOptions(
            showIcon: showIcon,
            showDayOfWeek: showDayOfWeek,
            showMonth: false,
            showDate: false,
            showYear: false,
            showFilledBackground: showFilledBackground
        )
    }

    @Test
    func render_returnsNonEmptyImage() {
        let image = MenuBarItemRenderer.render(
            options: opts(), dateString: "Sun", isDark: false
        )
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
        #expect(!image.representations.isEmpty)
        // Not a template — we draw explicit colors the menu bar must not tint.
        #expect(image.isTemplate == false)
    }

    @Test
    func render_iconAndTextWiderThanIconOnly() {
        let iconOnly = MenuBarItemRenderer.render(
            options: opts(showDayOfWeek: false), dateString: "", isDark: false
        )
        let iconAndText = MenuBarItemRenderer.render(
            options: opts(), dateString: "Wednesday", isDark: false
        )
        // Adding text (plus the separator) must widen the item.
        #expect(iconAndText.size.width > iconOnly.size.width)
    }

    @Test
    func render_textOnlyOmitsIconWidth() {
        let textOnly = MenuBarItemRenderer.render(
            options: opts(showIcon: false), dateString: "Sun", isDark: false
        )
        let iconAndText = MenuBarItemRenderer.render(
            options: opts(showIcon: true), dateString: "Sun", isDark: false
        )
        // Dropping the icon (and separator) must narrow the item.
        #expect(textOnly.size.width < iconAndText.size.width)
    }

    @Test
    func render_emptyDateStillProducesIcon() {
        // With no text, the icon is always shown (menu bar item can't be empty).
        let image = MenuBarItemRenderer.render(
            options: opts(showIcon: false), dateString: "", isDark: false
        )
        #expect(image.size.width > 0)
    }

    @Test
    func render_filledAndBorderedBothValid() {
        let bordered = MenuBarItemRenderer.render(
            options: opts(showFilledBackground: false), dateString: "Sun", isDark: false
        )
        let filled = MenuBarItemRenderer.render(
            options: opts(showFilledBackground: true), dateString: "Sun", isDark: false
        )
        // Filled vs bordered keep the same width (only styling differs).
        #expect(abs(bordered.size.width - filled.size.width) < 0.5)
    }

    @Test
    func previewFollowsLightDarkLightOnSameMountedImageView() async throws {
        let appearance = PreviewAppearanceModel()
        let options = opts(showIcon: false)
        let host = AccessibilityTestHost(width: 180, height: 48) {
            AppearanceDrivenPreview(appearance: appearance, options: options)
        }
        defer { host.close() }
        try await host.settle()
        let imageView = try #require(imageViews(in: host.hosting).only)
        let initialSize = try #require(imageView.image).size

        for scheme in [ColorScheme.light, .dark, .light] {
            appearance.scheme = scheme
            try await host.settle()
            #expect(imageViews(in: host.hosting).only === imageView)
            let image = try #require(imageView.image)
            #expect(!image.isTemplate)
            #expect(imageView.imageScaling == .scaleNone)
            #expect(image.size == initialSize)
            let brightness = try opaqueTextBrightness(in: image)
            if scheme == .dark {
                #expect(brightness > 0.9, "Dark destination needs bright preview text")
            } else {
                #expect(brightness < 0.2, "Light destination needs dark preview text")
            }
        }
    }

    private func imageViews(in view: NSView) -> [NSImageView] {
        ((view as? NSImageView).map { [$0] } ?? [])
            + view.subviews.flatMap { imageViews(in: $0) }
    }

    private func opaqueTextBrightness(in image: NSImage) throws -> CGFloat {
        let data = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: data))
        var total: CGFloat = 0
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      color.alphaComponent > 0.98 else { continue }
                total += (color.redComponent + color.greenComponent + color.blueComponent) / 3
                count += 1
            }
        }
        try #require(count > 0, "Fixed text must produce opaque glyph pixels")
        return total / CGFloat(count)
    }
}

@MainActor
private final class PreviewAppearanceModel: ObservableObject {
    @Published var scheme: ColorScheme = .light
}

private struct AppearanceDrivenPreview: View {
    @ObservedObject var appearance: PreviewAppearanceModel
    let options: MenuBarDisplayOptions

    var body: some View {
        // Text only avoids the date icon's live day changing around midnight.
        StatusItemPreview(displayOptions: options, dateString: "Wednesday")
            .environment(\.colorScheme, appearance.scheme)
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
