import Foundation
import Testing
@testable import Glimpse

struct PanelGeometryTests {
    private let status = CGRect(x: 1000, y: 876, width: 100, height: 24)
    private let visible = CGRect(x: 0, y: 48, width: 1440, height: 828)

    // Catches capping against the entire visible height instead of the anchored budget.
    @Test(arguments: [
        (CGFloat(900), CGRect(x: 892, y: 58, width: 316, height: 812)),
        (CGFloat(824), CGRect(x: 892, y: 58, width: 316, height: 812)),
        (CGFloat(432), CGRect(x: 892, y: 438, width: 316, height: 432))
    ])
    func anchoredHeightFitsAboveBottomDock(desired: CGFloat, expected: CGRect) throws {
        let placement = try #require(PanelGeometry.placement(
            statusItemFrame: status, visibleFrame: visible, desiredHeight: desired
        ))
        #expect(placement.frame == expected)
        #expect(placement.caretXOffset == 158)
        #expect(placement.maximumHeight == 812)
        #expect(placement.frame.minY >= 58)
        #expect(placement.frame.maxY <= 876)
    }

    // These literal fixtures catch use of screen.frame rather than the Dock-adjusted visibleFrame.
    @Test(arguments: [
        (CGRect(x: 0, y: 876, width: 20, height: 24),
         CGRect(x: 0, y: 48, width: 1440, height: 828),
         CGRect(x: 10, y: 438, width: 316, height: 432), CGFloat(16)),
        (CGRect(x: 1420, y: 876, width: 20, height: 24),
         CGRect(x: 0, y: 48, width: 1440, height: 828),
         CGRect(x: 1114, y: 438, width: 316, height: 432), CGFloat(300)),
        (CGRect(x: 80, y: 876, width: 20, height: 24),
         CGRect(x: 80, y: 0, width: 1360, height: 876),
         CGRect(x: 90, y: 438, width: 316, height: 432), CGFloat(16)),
        (CGRect(x: 1340, y: 876, width: 20, height: 24),
         CGRect(x: 0, y: 0, width: 1360, height: 876),
         CGRect(x: 1034, y: 438, width: 316, height: 432), CGFloat(300)),
        (CGRect(x: -1200, y: 876, width: 100, height: 24),
         CGRect(x: -1440, y: 48, width: 1440, height: 828),
         CGRect(x: -1308, y: 438, width: 316, height: 432), CGFloat(158))
    ])
    func horizontalMarginsFollowVisibleScreen(
        status: CGRect, visible: CGRect, expected: CGRect, caret: CGFloat
    ) throws {
        let placement = try #require(PanelGeometry.placement(
            statusItemFrame: status, visibleFrame: visible, desiredHeight: 432
        ))
        #expect(placement.frame == expected)
        #expect(placement.caretXOffset == caret)
        #expect(placement.frame.minX >= visible.minX + 10)
        #expect(placement.frame.maxX <= visible.maxX - 10)
    }

    @Test
    func statusAboveScreenClampsTopToUsableDisplay() throws {
        let placement = try #require(PanelGeometry.placement(
            statusItemFrame: CGRect(x: 1000, y: 1000, width: 100, height: 24),
            visibleFrame: visible, desiredHeight: 900
        ))
        #expect(placement.frame == CGRect(x: 892, y: 58, width: 316, height: 818))
        #expect(placement.maximumHeight == 818)
    }

    @Test
    func minimumBodyAndCaretRemainDrawable() throws {
        let placement = try #require(PanelGeometry.placement(
            statusItemFrame: status, visibleFrame: visible, desiredHeight: 1
        ))
        #expect(placement.frame == CGRect(x: 892, y: 857, width: 316, height: 13))
    }

    @Test
    func exactMinimumAvailableHeightAndWidthAreSupported() throws {
        let placement = try #require(PanelGeometry.placement(
            statusItemFrame: CGRect(x: 150, y: 29, width: 20, height: 24),
            visibleFrame: CGRect(x: 0, y: 0, width: 336, height: 100),
            desiredHeight: 432
        ))
        #expect(placement.frame == CGRect(x: 10, y: 10, width: 316, height: 13))
        #expect(placement.maximumHeight == 13)
    }

    @Test
    func centeringRoundsBeforeClamping() throws {
        let placement = try #require(PanelGeometry.placement(
            statusItemFrame: CGRect(x: 1000.6, y: 876, width: 100, height: 24),
            visibleFrame: visible, desiredHeight: 432
        ))
        #expect(placement.frame.origin.x == 893)
        #expect(abs(placement.caretXOffset - 157.6) < 0.0001)
    }

    @Test(arguments: [CGFloat.zero, -1, .nan, .infinity, -.infinity])
    func rejectsInvalidDesiredHeight(desired: CGFloat) {
        #expect(PanelGeometry.placement(
            statusItemFrame: status, visibleFrame: visible, desiredHeight: desired
        ) == nil)
    }

    @Test(arguments: [
        CGRect(x: 0, y: 0, width: 335.9, height: 876),
        CGRect(x: 0, y: 0, width: 0, height: 876),
        CGRect(x: 0, y: 0, width: -1440, height: 876),
        CGRect(x: 0, y: 0, width: 1440, height: 0),
        CGRect(x: 0, y: 0, width: 1440, height: -876),
        CGRect(x: CGFloat.nan, y: 0, width: 1440, height: 876),
        CGRect(x: 0, y: CGFloat.infinity, width: 1440, height: 876),
        CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 876),
        CGRect(x: 0, y: 0, width: 1440, height: CGFloat.nan),
        CGRect(x: CGFloat.greatestFiniteMagnitude, y: 0,
               width: CGFloat.greatestFiniteMagnitude, height: 876)
    ])
    func rejectsInvalidVisibleGeometry(visible: CGRect) {
        #expect(PanelGeometry.placement(
            statusItemFrame: status, visibleFrame: visible, desiredHeight: 432
        ) == nil)
    }

    @Test(arguments: [
        CGRect(x: 1000, y: 876, width: 0, height: 24),
        CGRect(x: 1000, y: 876, width: 100, height: 0),
        CGRect(x: 1000, y: 876, width: -100, height: 24),
        CGRect(x: 1000, y: 876, width: 100, height: -24),
        CGRect(x: CGFloat.nan, y: 876, width: 100, height: 24),
        CGRect(x: 1000, y: -CGFloat.infinity, width: 100, height: 24),
        CGRect(x: 1000, y: 876, width: CGFloat.nan, height: 24),
        CGRect(x: 1000, y: 876, width: 100, height: CGFloat.infinity),
        CGRect(x: 1000, y: 76.9, width: 100, height: 24),
        CGRect(x: CGFloat.greatestFiniteMagnitude, y: 876,
               width: CGFloat.greatestFiniteMagnitude, height: 24)
    ])
    func rejectsInvalidOrImpossibleStatusAnchor(status: CGRect) {
        #expect(PanelGeometry.placement(
            statusItemFrame: status, visibleFrame: visible, desiredHeight: 432
        ) == nil)
    }

    @Test
    func repeatedPlacementIsDeterministic() throws {
        let first = try #require(PanelGeometry.placement(
            statusItemFrame: status, visibleFrame: visible, desiredHeight: 900
        ))
        for _ in 0..<20 {
            #expect(PanelGeometry.placement(
                statusItemFrame: status, visibleFrame: visible, desiredHeight: 900
            ) == first)
        }
    }

    // Catches omitting any component, and using <= instead of < at the convergence boundary.
    @Test(arguments: [0, 1, 2, 3], [CGFloat(0.49), 0.5, 1, -0.49, -0.5, -1])
    func frameComparisonRequiresEveryComponentBelowTolerance(component: Int, change: CGFloat) {
        let base = CGRect(x: 10, y: 20, width: 316, height: 432)
        var other = base
        switch component {
        case 0: other.origin.x += change
        case 1: other.origin.y += change
        case 2: other.size.width += change
        default: other.size.height += change
        }
        #expect(PanelGeometry.framesMatch(base, other) == (abs(change) < 0.5))
    }

    @Test(arguments: [
        CGRect(x: 10, y: 20, width: -316, height: 432),
        CGRect(x: 10, y: 20, width: 316, height: -432)
    ])
    func frameComparisonUsesRawSizeComponents(other: CGRect) {
        #expect(!PanelGeometry.framesMatch(CGRect(x: 10, y: 20, width: 316, height: 432), other))
    }
}
