import Foundation
import Observation

@MainActor @Observable
final class PanelLayoutState {
    private(set) var naturalContentHeight: CGFloat = 420
    private(set) var maximumHeight: CGFloat = 800
    private(set) var caretXOffset: CGFloat = 158

    var viewportHeight: CGFloat {
        min(naturalContentHeight, maximumHeight - PanelGeometry.caretHeight)
    }
    var totalHeight: CGFloat { viewportHeight + PanelGeometry.caretHeight }
    var isOverflowing: Bool {
        naturalContentHeight - viewportHeight > PanelGeometry.tolerance
    }

    func updateContentHeight(_ height: CGFloat) {
        guard height.isFinite, height > 0,
              abs(height - naturalContentHeight) >= PanelGeometry.tolerance
        else { return }
        naturalContentHeight = height
    }

    func updatePlacement(maximumHeight: CGFloat, caretXOffset: CGFloat) {
        guard maximumHeight.isFinite, maximumHeight >= PanelGeometry.caretHeight + 1,
              caretXOffset.isFinite,
              (PanelGeometry.caretInset...(PanelGeometry.panelWidth - PanelGeometry.caretInset))
                .contains(caretXOffset)
        else { return }
        if abs(maximumHeight - self.maximumHeight) >= PanelGeometry.tolerance {
            self.maximumHeight = maximumHeight
        }
        if abs(caretXOffset - self.caretXOffset) >= PanelGeometry.tolerance {
            self.caretXOffset = caretXOffset
        }
    }
}
