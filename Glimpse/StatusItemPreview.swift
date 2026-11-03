import AppKit
import GlimpseCore
import SwiftUI

/// Renders the preferences preview using the exact same image as the real menu
/// bar item (`MenuBarItemRenderer`), so the preview can never drift from reality.
struct StatusItemPreview: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    let displayOptions: MenuBarDisplayOptions
    let dateString: String

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleNone
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        // Match the destination window without observing/mutating status-item appearance.
        view.image = MenuBarItemRenderer.render(
            options: displayOptions,
            dateString: dateString,
            isDark: colorScheme == .dark
        )
    }
}
