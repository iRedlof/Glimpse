import AppKit
import SwiftUI

struct PanelViewport<Content: View>: View {
    let layout: PanelLayoutState
    private let content: Content

    init(layout: PanelLayoutState, @ViewBuilder content: () -> Content) {
        self.layout = layout
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical) {
            content
                .frame(width: PanelGeometry.contentWidth)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ContentHeightPreference.self,
                            value: geometry.size.height
                        )
                    }
                }
        }
        .scrollDisabled(!layout.isOverflowing)
        // Keep system indicators inside the rounded body without reducing the
        // natural content width or overriding the user's scroller style.
        .contentMargins(
            .trailing, NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy),
            for: .scrollIndicators
        )
        // Legacy scrollers can make the native host wider than this viewport.
        // Align its unchanged content with the body's leading edge.
        .frame(
            width: PanelGeometry.contentWidth, height: layout.viewportHeight,
            alignment: .leading
        )
        .onPreferenceChange(ContentHeightPreference.self) { height in
            // A measurement must not mutate observation during SwiftUI's layout pass.
            Task { @MainActor in
                layout.updateContentHeight(height)
            }
        }
    }
}

private struct ContentHeightPreference: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        // Hosted controls also contribute the default zero preference. Preserve
        // the actual measured child height across those contributions.
        value = max(value, nextValue())
    }
}
