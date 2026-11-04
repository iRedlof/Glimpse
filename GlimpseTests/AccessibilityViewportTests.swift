import AppKit
import ApplicationServices
import ComposableArchitecture
import EventKit
import GlimpseCore
import SwiftUI
import Testing

@testable import Glimpse

@Suite(.serialized) @MainActor
struct AccessibilityViewportTests {
    @Test(arguments: [CGFloat(812), 312], [
        (false, NSScroller.Style.legacy), (false, .overlay),
        (true, .legacy), (true, .overlay)
    ])
    func dateSearchTargetsRemainReachableAndCollapseInPersistentViewport(
        maximumHeight: CGFloat, presentation: (Bool, NSScroller.Style)
    ) async throws {
        let (processing, style) = presentation
        let controls = CalendarControlFixture(togglePinOnAction: false)
        let search = DateSearchFixture()
        let query = String(repeating: "synthetic next Friday ", count: 20)
        let error = String(repeating: "Synthetic date search error. ", count: 12)
        search.query = query
        search.error = error
        search.isProcessing = processing
        let layout = PanelLayoutState()
        layout.updatePlacement(maximumHeight: maximumHeight, caretXOffset: 158)
        let host = AccessibilityTestHost(width: 316, height: maximumHeight) {
            AccessibilityViewportContent(
                layout: layout, controls: controls, dateSearch: search
            )
        }
        defer { host.close() }
        try await host.settle()
        try host.loadAccessibilityWindowTree()
        try await host.settle()
        let scroll = try #require(accessibilityScrollView(in: host.hosting))
        let document = try #require(scroll.documentView)
        try await applyFixtureScrollerStyle(style, scroll: scroll, host: host)
        if processing {
            #expect(host.controls(named: "Close date search").isEmpty)
            #expect(search.query == query && search.error == error && search.isActive)
            #expect(search.submissions == 0)
            search.isProcessing = false
            try await host.settle()
        }
        for position in IconClickPosition.allCases {
            search.query = query
            search.error = error
            search.isActive = true
            try await host.settle()
            try await applyFixtureScrollerStyle(style, scroll: scroll, host: host)
            let beforeScroll = try host.control(named: "Close date search")
            _ = document.scrollToVisible(host.rect(beforeScroll.frame, in: document)
                .insetBy(dx: -16, dy: -16))
            scroll.reflectScrolledClipView(scroll.contentView)
            try await host.settle()
            let dismiss = try host.control(named: "Close date search")
            let editor = try #require(host.elements().first { $0.role == .textField })
            expectDateSearchTarget(dismiss.frame)
            let body = viewportBodyScreenRect(host: host, scroll: scroll, layout: layout)
            let clip = host.window.convertToScreen(
                scroll.contentView.convert(scroll.contentView.bounds, to: nil)
            )
            #expect(body.contains(dismiss.frame) && clip.contains(dismiss.frame))
            #expect(!editor.frame.intersects(dismiss.frame))
            if style == .legacy, let scroller = scroll.verticalScroller, !scroller.isHidden {
                let scrollerFrame = host.window.convertToScreen(
                    scroller.convert(scroller.bounds, to: nil)
                )
                #expect(!dismiss.frame.intersects(scrollerFrame))
            }
            try await host.click(atScreenPoint: position.point(in: dismiss.frame))
            #expect(search.query.isEmpty && search.error == nil && !search.isActive)
            #expect(!search.isProcessing && search.submissions == 0)
            #expect(host.window.isVisible)
            #expect(controls.receipts.isEmpty && !controls.isPinned)
            try await applyFixtureScrollerStyle(style, scroll: scroll, host: host)
            #expect(accessibilityScrollView(in: host.hosting) === scroll)
            #expect(scroll.documentView === document)
            let height = layout.naturalContentHeight
            let size = host.hosting.intrinsicContentSize
            for _ in 0..<4 {
                try await host.settle()
                #expect(layout.naturalContentHeight == height)
                #expect(host.hosting.intrinsicContentSize == size)
            }
            #expect(abs(size.width - 316) < 0.5)
            #expect(size.height <= maximumHeight + 0.5)
            #expect(abs(host.hosting.fittingSize.width - 316) < 0.5)
            #expect(host.hosting.fittingSize.height <= maximumHeight + 0.5)
            #expect(scroll.scrollerStyle == style)
            #expect(scroll.contentView.bounds.width >= 300)
        }
    }

    @Test(arguments: [CGFloat(812), 312], [
        (false, NSScroller.Style.legacy), (false, .overlay),
        (true, .legacy), (true, .overlay)
    ])
    func targetsFitAndRemainReachableInPersistentViewport(
        maximumHeight: CGFloat, presentation: (Bool, NSScroller.Style)
    ) async throws {
        let (pinned, style) = presentation
        let controls = CalendarControlFixture(togglePinOnAction: false)
        controls.isPinned = pinned
        let layout = PanelLayoutState()
        layout.updatePlacement(maximumHeight: maximumHeight, caretXOffset: 158)
        let host = AccessibilityTestHost(width: 316, height: maximumHeight) {
            AccessibilityViewportContent(layout: layout, controls: controls)
        }
        defer { host.close() }
        try await host.settle()
        let scroll = try #require(accessibilityScrollView(in: host.hosting))
        let document = try #require(scroll.documentView)
        try host.loadAccessibilityWindowTree()
        try await host.settle()
        try await applyFixtureScrollerStyle(style, scroll: scroll, host: host)
        var documentFrames: [CalendarControlAction: NSRect] = [:]
        for row in [CalendarControlAction.header, CalendarControlAction.footer] {
            let first = try host.control(named: controls.name(for: row[0]))
            let firstInDocument = host.rect(first.frame, in: document)
            _ = document.scrollToVisible(firstInDocument.insetBy(dx: -16, dy: -16))
            scroll.reflectScrolledClipView(scroll.contentView)
            try await host.settle()
            #expect(scroll.scrollerStyle == style)
            #expect(scroll.contentView.bounds.width >= 300)
            let body = viewportBodyScreenRect(host: host, scroll: scroll, layout: layout)
            let clip = host.window.convertToScreen(
                scroll.contentView.convert(scroll.contentView.bounds, to: nil)
            )
            let rowFrames = try row.map { try host.control(named: controls.name(for: $0)).frame }
            expectDisjointIconRow(rowFrames, minimumGap: row == CalendarControlAction.footer ? 4 : 8)
            for action in row {
                let node = try host.control(named: controls.name(for: action))
                expectCalendarControlTarget(node.frame, action: action)
                #expect(body.contains(node.frame), "Target \(action) outside body \(body)")
                #expect(clip.contains(node.frame), "Target \(action) clipped by \(clip)")
                if style == .legacy, let scroller = scroll.verticalScroller, !scroller.isHidden {
                    let scrollerFrame = host.window.convertToScreen(
                        scroller.convert(scroller.bounds, to: nil)
                    )
                    #expect(!node.frame.intersects(scrollerFrame),
                            "Target \(action) \(node.frame) overlaps scrollbar \(scrollerFrame)")
                }
                let inDocument = host.rect(node.frame, in: document)
                documentFrames[action] = inDocument
                #expect(inDocument.minX >= 15.5)
                #expect(inDocument.maxX <= 284.5)
                for position in IconClickPosition.allCases {
                    let before = controls.receipts
                    try await host.click(atScreenPoint: position.point(in: node.frame))
                    var expected = before
                    expected[action, default: 0] += 1
                    #expect(controls.receipts == expected,
                            "\(action) \(position), frame \(node.frame), clip \(clip), actual style \(scroll.scrollerStyle.rawValue)")
                }
            }
        }
        #expect(documentFrames.count == 8)
        let allocations = Array(documentFrames.values)
        for (index, frame) in allocations.enumerated() {
            for other in allocations.dropFirst(index + 1) {
                #expect(!frame.intersects(other))
            }
        }
        #expect(controls.isPinned == pinned)
        for pinState in [!pinned, pinned] {
            controls.isPinned = pinState
            try await host.settle()
            try await applyFixtureScrollerStyle(style, scroll: scroll, host: host)
            #expect(accessibilityScrollView(in: host.hosting) === scroll)
            #expect(scroll.documentView === document)
            #expect(try host.control(named: "Open Glimpse Settings").role == .button)
        }
        let height = layout.naturalContentHeight
        let size = host.hosting.intrinsicContentSize
        for _ in 0..<4 {
            try await host.settle()
            #expect(layout.naturalContentHeight == height)
            #expect(host.hosting.intrinsicContentSize == size)
            #expect(accessibilityScrollView(in: host.hosting) === scroll)
        }
        #expect(abs(size.width - 316) < 0.5)
        #expect(size.height <= maximumHeight + 0.5)
        #expect(abs(host.hosting.fittingSize.width - 316) < 0.5)
        #expect(host.hosting.fittingSize.height <= maximumHeight + 0.5)
        #expect(scroll.scrollerStyle == style)
        #expect(scroll.contentView.bounds.width >= 300)
    }

    @Test(arguments: [CGFloat(812), 312], [NSScroller.Style.legacy, .overlay])
    func completeCalendarDatesAndFooterRemainReachable(
        maximumHeight: CGFloat, style: NSScroller.Style
    ) async throws {
        let layout = PanelLayoutState()
        layout.updatePlacement(maximumHeight: maximumHeight, caretXOffset: 158)
        let fixture = try CalendarViewportFixture(layout: layout, maximumHeight: maximumHeight)
        let host = fixture.host
        defer { fixture.close() }
        try await host.settle()
        try host.loadAccessibilityWindowTree()
        try await host.settle()
        let scroll = try #require(accessibilityScrollView(in: host.hosting))
        let document = try #require(scroll.documentView)
        try await applyFixtureScrollerStyle(style, scroll: scroll, host: host)
        let dates = host.elements().filter { $0.role == .button && $0.label?.contains("2030") == true }
        #expect(dates.count == 42, "The real calendar must expose every date\n\(host.treeDescription)")
        let dateNames = dates.compactMap(\.label)
        #expect(Set(dateNames).count == 42)
        let controls = [
            "Previous month", "Go to today", "Next month",
            "Quit Glimpse", "About Glimpse", "Pin calendar window",
            "Open Calendar app", "Open Glimpse Settings",
        ]
        var dateFrames: [NSRect] = []
        for name in dateNames + controls {
            let beforeScroll = try host.control(named: name)
            _ = document.scrollToVisible(host.rect(beforeScroll.frame, in: document)
                .insetBy(dx: -4, dy: -4))
            scroll.reflectScrolledClipView(scroll.contentView)
            try await host.settle()
            let node = try host.control(named: name)
            let body = viewportBodyScreenRect(host: host, scroll: scroll, layout: layout)
            let clip = host.window.convertToScreen(
                scroll.contentView.convert(scroll.contentView.bounds, to: nil)
            )
            #expect(body.contains(node.frame), "\(name) outside calendar body \(body)")
            #expect(clip.contains(node.frame), "\(name) clipped by calendar viewport \(clip)")
            if style == .legacy, let scroller = scroll.verticalScroller, !scroller.isHidden {
                let scrollerFrame = host.window.convertToScreen(
                    scroller.convert(scroller.bounds, to: nil)
                )
                #expect(!node.frame.intersects(scrollerFrame), "\(name) overlaps the scrollbar")
            }
            if dateNames.contains(name) {
                #expect(node.enabled)
                #expect(abs(node.frame.height - 30) < 0.5)
                #expect(node.frame.width > 28)
                dateFrames.append(host.rect(node.frame, in: document))
            }
            #expect(accessibilityScrollView(in: host.hosting) === scroll)
            #expect(scroll.documentView === document)
        }
        for (index, frame) in dateFrames.enumerated() {
            for other in dateFrames.dropFirst(index + 1) {
                #expect(!frame.intersects(other))
            }
        }
        #expect(fixture.store.displayedMonth == fixture.month)
        #expect(fixture.store.selectedDate == nil)
        #expect(fixture.protectedEffects.value == 0)
        let height = layout.naturalContentHeight
        let size = host.hosting.intrinsicContentSize
        for _ in 0..<4 {
            try await host.settle()
            #expect(layout.naturalContentHeight == height)
            #expect(host.hosting.intrinsicContentSize == size)
        }
        #expect(abs(size.width - 316) < 0.5)
        #expect(size.height <= maximumHeight + 0.5)
        #expect(abs(host.hosting.fittingSize.width - 316) < 0.5)
        #expect(host.hosting.fittingSize.height <= maximumHeight + 0.5)
        #expect(scroll.scrollerStyle == style)
        #expect(scroll.contentView.bounds.width >= 300)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GLIMPSE_CALENDAR_LIVE_CAPTURE_DIR"] != nil))
    func productionCalendarSystemCompositorCapture() async throws {
        let environment = ProcessInfo.processInfo.environment
        let path = try #require(environment["GLIMPSE_CALENDAR_LIVE_CAPTURE_DIR"])
        try #require(path.hasPrefix("/"), "Live capture requires an absolute owned internal-runtime directory")
        let directory = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        try #require(directory.resolvingSymlinksInPath() == directory, "Use the canonical owned directory")
        var isDirectory: ObjCBool = false
        try #require(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory)
                     && isDirectory.boolValue, "Root must prepare the owned directory before this test")
        let bitmapPath = try #require(environment["GLIMPSE_CONTRAST_ARTIFACT_DIR"])
        try #require(URL(fileURLWithPath: bitmapPath, isDirectory: true).standardizedFileURL == directory,
                     "Paired hosting evidence must use the same owned destination")
        let scenario = try #require(CalendarContrastScenario(
            rawValue: environment["GLIMPSE_CALENDAR_LIVE_SCENARIO"] ?? "selectedEmpty"
        ), "Choose an existing synthetic contrast scenario")
        try #require(scenario != .selectedLoading && scenario != .aiProcessing,
                     "Five-second held-client watchdogs cannot support a sixty-second live checkpoint")
        let phase = environment["GLIMPSE_CALENDAR_LIVE_CAPTURE_PHASE"] ?? "active"
        try #require(phase == "active" || phase == "inactive")
        let expectsActive = phase == "active"
        let ready = directory.appendingPathComponent("ready.json")
        let acknowledgement = directory.appendingPathComponent("ack.json")
        try #require(!FileManager.default.fileExists(atPath: ready.path)
                     && !FileManager.default.fileExists(atPath: acknowledgement.path),
                     "Each invocation requires fresh readiness and acknowledgement paths")
        let screen = try #require(NSScreen.main ?? NSScreen.screens.first)
        let visible = screen.visibleFrame
        try #require(visible.width.isFinite && visible.height.isFinite && visible.width >= 316
                     && visible.height > 100)
        let fixture = try CalendarViewportFixture(
            contrastScenario: scenario, maximumHeight: min(812, visible.height - 32), observeLiveActivation: true
        )
        do {
            let hosting = try #require(fixture.contrastHosting)
            hosting.sizingOptions = []
            try await fixture.mountContrast(dark: nil)
            try fixture.expectContrastState()
            let panel = try #require(fixture.contrastPanel)
            try #require(panel.frame.width <= visible.width && panel.frame.height <= visible.height,
                         "The real panel must fit completely on the selected screen")
            let nonce = UUID().uuidString
            panel.title = "Glimpse synthetic calendar capture \(nonce)"
            panel.setFrameOrigin(NSPoint(x: visible.minX + (visible.width - panel.frame.width) / 4,
                                         y: visible.midY - panel.frame.height / 2))
            try await fixture.settleContrast()
            let frame = panel.frame
            let hostingBounds = hosting.bounds
            let pid = ProcessInfo.processInfo.processIdentifier
            let windowNumber = panel.windowNumber
            let title = panel.title
            let captureName = "compositor-\(nonce)-\(phase).png"
            try #require(windowNumber > 0 && visible.contains(frame))
            let activationNotifications = LockIsolated(0)
            let invalidActivationContexts = LockIsolated(0)
            let applicationIdentity = ObjectIdentifier(NSApp as NSApplication)
            let validateActivation: @MainActor @Sendable (Bool) -> Void = { notificationObjectMatches in
                activationNotifications.withValue { $0 += 1 }
                if !notificationObjectMatches || !NSApp.isActive
                    || !panel.isVisible || panel.contentView !== hosting || hosting.window !== panel {
                    invalidActivationContexts.withValue { $0 += 1 }
                }
            }
            let observer = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: NSApp, queue: .main
            ) { notification in
                let notificationObjectMatches = ObjectIdentifier(notification.object as AnyObject) == applicationIdentity
                MainActor.assumeIsolated {
                    validateActivation(notificationObjectMatches)
                }
            }
            defer { NotificationCenter.default.removeObserver(observer) }
            let expectedRefreshCompletions = expectsActive && scenario.authorization == .fullAccess ? 1 : 0
            let expectedFetches = scenario.authorization == .fullAccess ? (expectsActive ? 2 : 1) : 0
            var activationRefreshCompleted = false

            @MainActor
            func validateCaptureState(requireActivity: Bool, requireScenario: Bool = true) throws {
                try #require(panel.isVisible && panel.isPinned && fixture.store.isPinned
                             && panel.contentView === hosting && hosting.window === panel
                             && panel.frame == frame && hosting.bounds == hostingBounds
                             && panel.windowNumber == windowNumber && panel.title == title
                             && panel.appearance == nil && visible.contains(panel.frame))
                if requireActivity { try #require(NSApp.isActive == expectsActive) }
                if requireScenario {
                    try #require(activationNotifications.value == (activationRefreshCompleted ? 1 : 0)
                                 && invalidActivationContexts.value == 0
                                 && fixture.liveActivationRefreshes.value == (activationRefreshCompleted ? 1 : 0)
                                 && fixture.liveActivationCompletions.value == (activationRefreshCompleted ? expectedRefreshCompletions : 0)
                                 && fixture.liveInvalidCompletions.value == 0
                                 && fixture.liveSyntheticFetches == (scenario.authorization == .fullAccess
                                     ? (activationRefreshCompleted ? 2 : 1) : 0)
                                 && !fixture.store.isLoadingEvents && fixture.store.eventsRequestID == nil
                                 && fixture.protectedEffects.value == 0)
                    try fixture.expectContrastState(afterOwnedActivation: activationRefreshCompleted)
                }
                #expect(fixture.protectedEffects.value == 0)
            }

            @MainActor
            func publish(_ status: String, capture: [String: Any] = [:]) throws {
                var accent: [CGFloat] = []
                panel.effectiveAppearance.performAsCurrentDrawingAppearance {
                    if let color = NSColor.controlAccentColor.usingColorSpace(.deviceRGB) {
                        accent = [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
                    }
                }
                try #require(accent.count == 4 && accent.allSatisfy { $0.isFinite })
                let metadata: [String: Any] = [
                    "status": status, "nonce": nonce, "phase": phase, "pid": pid,
                    "windowNumber": windowNumber, "title": title,
                    "windowFrame": NSStringFromRect(frame),
                    "frameXYWH": [frame.minX, frame.minY, frame.width, frame.height],
                    "visibleFrame": NSStringFromRect(visible), "hostingBounds": NSStringFromRect(hostingBounds),
                    "backingScale": panel.backingScaleFactor, "scenario": scenario.rawValue, "state": scenario.rawValue,
                    "selectedDate": fixture.store.selectedDate.map { $0.timeIntervalSince1970 as Any } ?? NSNull(),
                    "loadingEvents": fixture.store.isLoadingEvents,
                    "effectiveAppearance": hosting.effectiveAppearance.name.rawValue,
                    "bestMatchAppearance": hosting.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])?.rawValue ?? "",
                    "nativeAccentRGBA": accent,
                    "reduceTransparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                    "increaseContrast": NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
                    "expectedAppActive": expectsActive, "actualAppActive": NSApp.isActive,
                    "calendarKey": panel.isKeyWindow, "protectedEffects": fixture.protectedEffects.value,
                    "ownedActivationNotifications": activationNotifications.value,
                    "invalidActivationContexts": invalidActivationContexts.value,
                    "activationRefreshActions": fixture.liveActivationRefreshes.value,
                    "matchingRefreshCompletions": fixture.liveActivationCompletions.value,
                    "invalidRefreshCompletions": fixture.liveInvalidCompletions.value,
                    "activationRefreshCompleted": activationRefreshCompleted,
                    "refreshCompletionQualification": "Matching current request ID/date action plus settled public state; not a hidden effect Task.value join",
                    "expectedSyntheticFetches": expectedFetches, "actualSyntheticFetches": fixture.liveSyntheticFetches,
                    "pairedHostingPhase": "live-\(nonce)-\(phase)",
                    "expectedCaptureFilename": captureName, "capture": capture,
                    "qualification": "Synthetic accessibility-enabled root inheriting actual OS appearance; hosting bitmap is paired evidence, not a compositor screenshot"
                ]
                try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys, .prettyPrinted])
                    .write(to: ready, options: .atomic)
                print("GLIMPSE_CALENDAR_LIVE_READY status=\(status) nonce=\(nonce) pid=\(pid) window=\(windowNumber) phase=\(phase)")
            }

            let deadline = ContinuousClock.now.advanced(by: .seconds(60))
            try validateCaptureState(requireActivity: false)
            try publish("awaiting-activity")
            if expectsActive {
                try #require(!NSApp.isActive, "Active capture must witness a real owned inactive-to-active transition")
                NSApp.activate(ignoringOtherApps: true)
                while !NSApp.isActive || activationNotifications.value != 1
                    || fixture.liveActivationRefreshes.value != 1
                    || fixture.liveActivationCompletions.value != expectedRefreshCompletions
                    || fixture.store.isLoadingEvents || fixture.store.eventsRequestID != nil {
                    try #require(activationNotifications.value <= 1 && invalidActivationContexts.value == 0
                                 && fixture.liveActivationRefreshes.value <= 1
                                 && fixture.liveActivationCompletions.value <= expectedRefreshCompletions
                                 && fixture.liveInvalidCompletions.value == 0
                                 && fixture.liveSyntheticFetches <= expectedFetches
                                 && fixture.protectedEffects.value == 0,
                                 "Extra activation, refresh, completion or protected effects cannot pass")
                    guard ContinuousClock.now < deadline else { throw CalendarContrastFixtureFailure.stateTimeout }
                    try await Task.sleep(for: .milliseconds(50))
                    try validateCaptureState(requireActivity: false, requireScenario: false)
                }
                activationRefreshCompleted = true
            } else {
                while NSApp.isActive {
                    guard ContinuousClock.now < deadline else { throw CalendarContrastFixtureFailure.stateTimeout }
                    try await Task.sleep(for: .milliseconds(50))
                    try validateCaptureState(requireActivity: false)
                }
            }
            try validateCaptureState(requireActivity: true)
            try fixture.captureContrastState("live-\(nonce)-\(phase)")
            try validateCaptureState(requireActivity: true)
            try publish("capture-ready")
            while !FileManager.default.fileExists(atPath: acknowledgement.path) {
                guard ContinuousClock.now < deadline else { throw CalendarContrastFixtureFailure.stateTimeout }
                try await Task.sleep(for: .milliseconds(50))
                try validateCaptureState(requireActivity: true)
            }
            try #require(ContinuousClock.now < deadline, "Late acknowledgements cannot pass")
            try #require(acknowledgement.resolvingSymlinksInPath() == acknowledgement)
            let ackAttributes = try FileManager.default.attributesOfItem(atPath: acknowledgement.path)
            let ackBytes = try #require(ackAttributes[.size] as? NSNumber).intValue
            try #require(ackAttributes[.type] as? FileAttributeType == .typeRegular
                         && ackBytes > 0 && ackBytes <= 16_384)
            let ackData = try Data(contentsOf: acknowledgement)
            let decodedAck = try JSONSerialization.jsonObject(with: ackData)
            let ack = try #require(decodedAck as? [String: Any])
            try #require(ack["nonce"] as? String == nonce && ack["phase"] as? String == phase
                         && ack["pid"] as? Int == Int(pid) && ack["windowNumber"] as? Int == windowNumber
                         && ack["title"] as? String == title && ack["captureKind"] as? String == "native-compositor",
                         "Root must acknowledge the exact owned capture identity")
            let capturePath = try #require(ack["capturePath"] as? String)
            try #require(capturePath.hasPrefix("/"))
            let captureURL = URL(fileURLWithPath: capturePath).standardizedFileURL
            try #require(captureURL.deletingLastPathComponent() == directory
                         && captureURL.resolvingSymlinksInPath() == captureURL
                         && captureURL.lastPathComponent == captureName)
            let attributes = try FileManager.default.attributesOfItem(atPath: captureURL.path)
            let bytes = try #require(attributes[.size] as? NSNumber).intValue
            try #require(attributes[.type] as? FileAttributeType == .typeRegular
                         && bytes > 0 && ack["captureBytes"] as? Int == bytes,
                         "The acknowledged compositor PNG must be a nonempty owned file")
            try validateCaptureState(requireActivity: true)
            try publish("capture-acknowledged", capture: [
                "path": captureURL.path, "bytes": bytes,
                "qualification": "Root acknowledged compositor capture; fixture does not perform or independently prove the CUA capture"
            ])
        } catch {
            try await fixture.drainContrastWork()
            throw error
        }
        try await fixture.drainContrastWork()
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GLIMPSE_CALENDAR_KEYBOARD_ACCEPTANCE"] == "1"),
          arguments: CalendarContrastScenario.allCases, [false, true])
    func productionCalendarTextRolesHaveOwnedCaptures(
        scenario: CalendarContrastScenario, dark: Bool
    ) async throws {
        let fixture = try CalendarViewportFixture(contrastScenario: scenario, maximumHeight: 812)
        do {
            try await fixture.mountContrast(dark: dark)
            try fixture.expectContrastState()
            let panel = try #require(fixture.contrastPanel)
            try #require(!panel.layoutState.isOverflowing,
                         "The full-role capture must expose the complete production document")
            try await fixture.revealContrastFooter()
            try fixture.captureContrastState("full")
        } catch {
            try await fixture.drainContrastWork()
            throw error
        }
        try await fixture.drainContrastWork()
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GLIMPSE_CALENDAR_KEYBOARD_ACCEPTANCE"] == "1"),
          arguments: [NSScroller.Style.legacy, .overlay], [false, true])
    func productionCalendarContrastRowsRemainReachable(
        style: NSScroller.Style, dark: Bool
    ) async throws {
        for scenario in [CalendarContrastScenario.multipleEvents, .selectedQueryError, .accessDenied, .aiTransportError] {
            let fixture = try CalendarViewportFixture(contrastScenario: scenario, maximumHeight: 312)
            do {
                try await fixture.mountContrast(dark: dark)
                let hosting = try #require(fixture.contrastHosting)
                let scroll = try #require(accessibilityScrollView(in: hosting))
                let document = try #require(scroll.documentView)
                scroll.scrollerStyle = style
                scroll.tile()
                try await fixture.settleContrast()
                try fixture.expectContrastState()
                let texts: [String]
                switch scenario {
                case .multipleEvents:
                    texts = fixture.store.events.prefix(5).map { "\($0.title), \($0.timeString)" } + ["+2 more"]
                case .selectedQueryError: texts = ["Couldn’t load events.", "Retry loading calendar events"]
                case .accessDenied: texts = ["Calendar access is off."]
                case .aiTransportError: texts = [try #require(fixture.contrastModel?.errorMessage)]
                default: throw CalendarContrastFixtureFailure.stateTimeout
                }
                let targets = fixture.contrastNodes().filter { node in
                    node.label?.hasPrefix("Calendar events for ") == true ||
                        texts.contains { $0 == node.label || $0 == (node.value as? String) }
                }
                try #require(!targets.isEmpty, "The requested contrast row must actually exist")
                for text in texts {
                    try #require(targets.contains { $0.label == text || ($0.value as? String) == text },
                                 "A missing required row must not pass on the agenda heading alone")
                }
                for (index, target) in targets.enumerated() {
                    try await fixture.revealContrastRole(target)
                    #expect(accessibilityScrollView(in: hosting) === scroll && scroll.documentView === document)
                    #expect(scroll.scrollerStyle == style)
                    try fixture.captureContrastState("row-\(style.rawValue)-\(index)")
                }
                try await fixture.revealContrastFooter()
                try fixture.captureContrastState("footer-\(style.rawValue)")
            } catch {
                try await fixture.drainContrastWork()
                throw error
            }
            try await fixture.drainContrastWork()
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GLIMPSE_CALENDAR_KEYBOARD_ACCEPTANCE"] == "1"),
          arguments: [false, true], [false, true])
    func productionCalendarSemanticStatesRetainNativeAppearance(
        dark: Bool, peerOwnsKey: Bool
    ) async throws {
        let publicToday = Date()
        let fixture = try CalendarKeyboardRootFixture(showAI: true, maximumHeight: 812, initialToday: publicToday)
        let peer = CalendarKeyboardOwnedPeer()
        defer { peer.close(); fixture.close() }
        try await fixture.open()
        fixture.panel.appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        await fixture.settleRendering()
        #expect(fixture.hosting.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
                == (dark ? .darkAqua : .aqua))
        try #require(Calendar.current.isDateInToday(publicToday), "Reject public-clock midnight rollover")
        let other = try #require(fixture.store.days.first {
            $0.isCurrentMonth && !fixture.store.calendar.isDateInToday($0.date)
        }?.date)
        let outside = try #require(fixture.store.days.first { !$0.isCurrentMonth }?.date)
        try #require(ProcessInfo.processInfo.environment["GLIMPSE_KEYBOARD_ARTIFACT_DIR"] != nil,
                     "Semantic acceptance requires the existing owned keyboard capture destination")
        @MainActor
        func capture(_ state: String) throws {
            let bounds = fixture.panel.convertToScreen(fixture.hosting.convert(fixture.hosting.bounds, to: nil))
            let name = "contrast-semantic-\(dark ? "dark" : "light")-\(peerOwnsKey ? "peer-case" : "key-case")-\(state)"
            try fixture.saveFocusedDateBitmap(
                bounds, name: name
            )
            let nodes = fixture.accessibilityNodes()
            try #require(nodes.count <= 512)
            let rows: [[String: Any]] = nodes.map { node in
                ["role": node.role?.rawValue ?? "", "label": String((node.label ?? "").prefix(200)),
                 "value": String(((node.value as? String) ?? "").prefix(200)),
                 "frameInHosting": NSStringFromRect(fixture.hosting.convert(
                    fixture.panel.convertFromScreen(node.frame), from: nil
                 )), "enabled": node.enabled, "selected": node.selected,
                 "windowOwned": node.object.accessibilityWindow?() as? NSWindow === fixture.panel]
            }
            let scroll = try #require(accessibilityScrollView(in: fixture.hosting))
            let responder = fixture.panel.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
            let metadata: [String: Any] = [
                "source": "Glimpse/CalendarPopoverView.swift", "testSource": #filePath, "state": state,
                "appearance": fixture.hosting.effectiveAppearance.name.rawValue,
                "calendarKey": fixture.panel.isKeyWindow, "ownedPeerKey": peer.panel.isKeyWindow,
                "appActive": NSApp.isActive, "owner": fixture.lastPublishedOwner?.rawValue ?? "nil",
                "responderClass": responder, "gridFocused": fixture.gridRenderingFocused,
                "publicToday": publicToday.timeIntervalSince1970,
                "selectedDate": fixture.store.selectedDate.map { $0.timeIntervalSince1970 as Any } ?? NSNull(),
                "displayedMonth": fixture.store.displayedMonth.timeIntervalSince1970,
                "windowFrame": NSStringFromRect(fixture.panel.frame),
                "hostingBounds": NSStringFromRect(fixture.hosting.bounds),
                "clipBounds": NSStringFromRect(scroll.contentView.bounds),
                "documentBounds": NSStringFromRect(scroll.documentView?.bounds ?? .zero),
                "backingScale": fixture.panel.backingScaleFactor, "nodes": rows,
                "qualification": "Window-local appearance and real owned key/peer state; nonkey does not prove app inactivity; AX groups do not prove per-glyph contrast"
            ]
            let directory = URL(fileURLWithPath: try #require(
                ProcessInfo.processInfo.environment["GLIMPSE_KEYBOARD_ARTIFACT_DIR"]
            ), isDirectory: true)
            let output = directory.appendingPathComponent(name + ".json")
            try #require(!FileManager.default.fileExists(atPath: output.path))
            try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys, .prettyPrinted]).write(to: output)
            print("GLIMPSE_CONTRAST_SEMANTIC state=\(state) calendarKey=\(fixture.panel.isKeyWindow) appActive=\(NSApp.isActive) owner=\(fixture.lastPublishedOwner?.rawValue ?? "nil") gridFocused=\(fixture.gridRenderingFocused) frame=\(fixture.panel.frame) responder=\(responder) metadata=\(output.path)")
        }
        for (state, selected) in [("no-selection", Optional<Date>.none), ("today-selected", Optional(publicToday)),
                                  ("other-selected", Optional(other)), ("outside-selected", Optional(outside))] {
            if let selected {
                fixture.store.send(.dateTapped(selected))
                if fixture.store.selectedDate == nil { fixture.store.send(.dateTapped(selected)) }
            } else if let selected = fixture.store.selectedDate {
                fixture.store.send(.dateTapped(selected))
            }
            await fixture.settleRendering()
            try await fixture.focusOwner(.grid)
            #expect(fixture.gridRenderingFocused)
            if state == "other-selected" || state == "outside-selected" {
                let beforeMovement = fixture.callbackRows.count
                try fixture.send(.right)
                fixture.expectInvocation(after: beforeMovement, owner: .grid, key: .right, route: "move(1)")
                await fixture.settleRendering()
                #expect(fixture.store.selectedDate == selected)
            }
            try fixture.loadOwnedAccessibilityTree()
            let nodes = fixture.accessibilityNodes()
            let dateLabels = fixture.store.days.map {
                $0.date.formatted(Date.FormatStyle.dateTime.weekday(.wide).month(.wide).day().year())
            }
            #expect(nodes.filter { node in
                node.role == .button && dateLabels.contains { node.label?.hasPrefix($0) == true }
            }.count == 42)
            #expect(nodes.filter { $0.role == .button && $0.label?.contains("outside current month") == true }.count > 0)
            let today = try fixture.ownedControl("Go to today")
            let isTodaySelected = selected.map { Calendar.current.isDate($0, inSameDayAs: publicToday) } == true
            #expect(today.enabled == !isTodaySelected)
            #expect(nodes.filter { $0.role == .button && $0.label?.contains(", today") == true }.count == 1)
            #expect(nodes.filter { $0.role == .button && $0.selected }.count == (selected == nil ? 0 : 1))
            if peerOwnsKey { try peer.makeKey(); await fixture.settleRendering() }
            #expect(NSApp.keyWindow === (peerOwnsKey ? peer.panel : fixture.panel))
            try capture(state)
            fixture.panel.makeKeyAndOrderFront(nil)
            await fixture.settleRendering()
        }
        for owner in [CalendarKeyboardOwner.previousMonth, .searchPrompt, .footerQuit] {
            try await fixture.focusOwner(owner)
            #expect(fixture.lastPublishedOwner == owner)
            try capture("focus-\(owner.rawValue)")
        }
        let callbacks = fixture.callbackRows.count
        try fixture.send(.returnKey)
        fixture.expectInvocation(after: callbacks, owner: .footerQuit, key: .returnKey, route: "activate")
        await fixture.settleRendering()
        try #require(fixture.lastPublishedOwner == .quitCancel)
        #expect(fixture.terminationReceipts == 0)
        try capture("quit-cancel-focus")
        try await fixture.focusOwner(.quitConfirm)
        #expect(fixture.lastPublishedOwner == .quitConfirm)
        try capture("quit-confirm-focus")
        try fixture.send(.escape)
        await fixture.settleRendering()
        #expect(fixture.lastPublishedOwner == .footerQuit)
        #expect(fixture.submissions.isEmpty && fixture.terminationReceipts == 0)
        try await fixture.focusOwner(.previousMonth)
        let beforePrevious = fixture.callbackRows.count
        try fixture.send(.returnKey)
        fixture.expectInvocation(after: beforePrevious, owner: .previousMonth, key: .returnKey, route: "activate")
        await fixture.settleRendering()
        #expect(!fixture.store.isShowingCurrentMonth)
        #expect(try fixture.ownedControl("Go to today").enabled)
        try capture("away-month-today-enabled")
        try await fixture.focusOwner(.today)
        let beforeToday = fixture.callbackRows.count
        try fixture.send(.returnKey)
        fixture.expectInvocation(after: beforeToday, owner: .today, key: .returnKey, route: "activate")
        await fixture.settleRendering()
        #expect(fixture.store.isShowingCurrentMonth)
        #expect(fixture.store.selectedDate == publicToday)
        #expect(try fixture.ownedControl("Go to today").enabled == false)
        #expect(Array(fixture.actionCurrentEvents.value.suffix(2)) == [true, true])
        #expect(fixture.submissions.isEmpty && fixture.terminationReceipts == 0
                && fixture.previousAppRestorations == 0 && fixture.aiSettingSaves.value.isEmpty)
        try #require(Calendar.current.isDateInToday(publicToday), "Reject public-clock midnight rollover")
    }
}

@MainActor
private func applyFixtureScrollerStyle(
    _ style: NSScroller.Style, scroll: NSScrollView, host: AccessibilityTestHost
) async throws {
    scroll.scrollerStyle = style
    scroll.tile()
    try await host.settle()
    #expect(scroll.scrollerStyle == style)
}

@MainActor
struct AccessibilityViewportContent: View {
    let layout: PanelLayoutState
    let controls: CalendarControlFixture
    var dateSearch: DateSearchFixture? = nil

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: CalendarPanel.caretHeight)
            PanelViewport(layout: layout) {
                VStack(spacing: 12) {
                    controls.header
                    if let dateSearch {
                        DateSearchFixtureRow(fixture: dateSearch)
                    }
                    Color.clear.frame(height: 300)
                    Divider()
                    controls.footer
                }
                .padding(AppDesign.Spacing.md)
            }
            .background(
                RoundedRectangle(cornerRadius: AppDesign.CornerRadius.lg)
                    .fill(.regularMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppDesign.CornerRadius.lg))
        }
        .frame(width: PanelGeometry.panelWidth)
    }
}

/// Explicit synthetic states for production-calendar paint coverage.
enum CalendarContrastScenario: String, CaseIterable, Sendable {
    case selectedResult, selectedEmpty, selectedLoading, selectedQueryError
    case noSelectionToday, selectedToday, multipleEvents
    case accessNotDetermined, accessDenied, accessRestricted, accessWriteOnly, accessRequesting, accessError
    case searchClosed, searchOpen, aiNoDate, aiTransportError, aiUnavailable, aiProcessing

    var authorization: EKAuthorizationStatus {
        switch self {
        case .accessNotDetermined, .accessRequesting: .notDetermined
        case .accessDenied, .accessError: .denied
        case .accessRestricted: .restricted
        case .accessWriteOnly: .writeOnly
        default: .fullAccess
        }
    }

    var opensSearch: Bool {
        [.searchOpen, .aiNoDate, .aiTransportError, .aiUnavailable, .aiProcessing].contains(self)
    }
}

private enum CalendarContrastFixtureFailure: Error {
    case syntheticQuery, stateTimeout
}

/// The legacy nonkey host remains intact; contrast mode owns a production panel.
@MainActor
private final class CalendarViewportFixture {
    let month: Date
    let store: StoreOf<CalendarFeature>
    private var legacyHost: AccessibilityTestHost?
    var host: AccessibilityTestHost {
        guard let legacyHost else { preconditionFailure("Contrast mode uses its owned production panel") }
        return legacyHost
    }
    let protectedEffects = LockIsolated(0)
    private(set) var contrastPanel: CalendarPanel?
    private(set) var contrastHosting: NSHostingView<AnyView>?
    private(set) var contrastModel: AIDateQueryModel?
    private var contrastScenario: CalendarContrastScenario?
    private var contrastAppearance: NSAppearance.Name?
    private var expectedEvents: [CalendarEvent] = []
    private var expectedSelection: Date?
    private let syntheticFetches = LockIsolated(0)
    let liveActivationRefreshes = LockIsolated(0)
    let liveActivationCompletions = LockIsolated(0)
    let liveInvalidCompletions = LockIsolated(0)
    var liveSyntheticFetches: Int { syntheticFetches.value }
    private let syntheticAIResolutions = LockIsolated(0)
    private let syntheticAICalls = LockIsolated(0)
    private let fetchEntered = AIDateIntegrationSignal<Void>("contrast synthetic fetch entered")
    private let fetchReturned = AIDateIntegrationSignal<Void>("contrast synthetic fetch returned")
    private let fetchRelease = AIDateIntegrationSignal<[CalendarEvent]>("contrast loading release")
    private let aiRelease = AIDateIntegrationSignal<Void>("contrast AI progress release")
    private var aiReceipt: AIDateIntegrationTrackedTask?

    init(layout: PanelLayoutState, maximumHeight: CGFloat) throws {
        month = try #require(Calendar.current.date(from: DateComponents(
            year: 2030, month: 11, day: 15, hour: 12
        )))
        let effects = protectedEffects
        let today = month
        store = Store(initialState: CalendarFeature.State(displayedMonth: month)) {
            CalendarFeature()
        } withDependencies: {
            $0.date = .constant(today)
            $0.calendarClient = .liveValue // Pure grid/date generation; no service I/O.
            $0.calendarClient.menuBarDateString = { _, _ in
                effects.withValue { $0 += 1 }
                Issue.record("Viewport fixture must not render a production status item")
                return ""
            }
            $0.preferencesClient = .testValue
            $0.preferencesClient.loadStartOfWeekday = { 1 }
            $0.preferencesClient.loadWorkdays = { [2, 3, 4, 5, 6] }
            $0.preferencesClient.loadShowAISearch = { false }
            $0.eventKitClient = EventKitClient(
                requestAccess: {
                    effects.withValue { $0 += 1 }
                    Issue.record("Viewport fixture must not request calendar access")
                    return false
                },
                fetchEvents: { _ in
                    effects.withValue { $0 += 1 }
                    Issue.record("Viewport fixture must not read private events")
                    return []
                },
                authorizationStatus: { .notDetermined }
            )
        }
        let calendarStore = store
        let model = AIDateQueryModel(
            client: AIDateQueryClient(
                resolveProvider: { _ in
                    effects.withValue { $0 += 1 }
                    Issue.record("Viewport fixture must not resolve an AI provider")
                    return .none
                },
                parseDate: { _, _ in
                    effects.withValue { $0 += 1 }
                    Issue.record("Viewport fixture must not request an AI date")
                    return nil
                }
            ),
            enabled: false, preference: .auto,
            onDate: { _ in Issue.record("Viewport fixture must not receive an AI date") }
        )
        legacyHost = AccessibilityTestHost(width: 316, height: maximumHeight) {
            CalendarPopoverView(
                store: calendarStore, layout: layout,
                aiQueryModel: model, loadAISettings: { (false, .auto) }
            )
        }
    }

    func close() {
        if let legacyHost {
            legacyHost.hosting.rootView = AnyView(EmptyView())
            legacyHost.close()
        }
    }

    init(
        contrastScenario scenario: CalendarContrastScenario, maximumHeight: CGFloat,
        observeLiveActivation: Bool = false
    ) throws {
        try #require(ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil,
                     "Production-panel captures are restricted to the owned test host")
        contrastScenario = scenario
        let publicToday = Date()
        month = try #require(Calendar.current.date(from: DateComponents(year: 2030, month: 11, day: 15, hour: 12)))
        let selected = try #require(Calendar.current.date(from: DateComponents(year: 2030, month: 11, day: 20, hour: 12)))
        let usesToday = scenario == .noSelectionToday || scenario == .selectedToday
        let clockDate = usesToday ? publicToday : month
        expectedSelection = scenario == .noSelectionToday ? nil : (usesToday ? publicToday : selected)
        let queriedDay = Calendar.current.startOfDay(for: expectedSelection ?? clockDate)
        let events: [CalendarEvent]
        if scenario == .selectedResult || scenario == .multipleEvents {
            let count = scenario == .multipleEvents ? 7 : 1
            events = try (0..<count).map { index in
                let start = try #require(Calendar.current.date(byAdding: .hour, value: index + 8, to: queriedDay))
                return CalendarEvent(id: "contrast-\(index)", title: "Synthetic event \(index + 1)",
                                     startDate: start, endDate: start.addingTimeInterval(3600),
                                     isAllDay: scenario == .multipleEvents && index == 0)
            }
        } else { events = [] }
        expectedEvents = events
        var state = CalendarFeature.State(displayedMonth: clockDate)
        state.selectedDate = expectedSelection
        state.isPinned = true
        state.calendarAuthorizationStatus = scenario.authorization
        state.isRequestingCalendarAccess = scenario == .accessRequesting
        if scenario == .accessError { state.calendarAccessError = "Synthetic calendar access failed." }
        let effects = protectedEffects
        let fetches = syntheticFetches
        let entered = fetchEntered
        let returned = fetchReturned
        let release = fetchRelease
        let refreshes = liveActivationRefreshes
        let completions = liveActivationCompletions
        let invalidCompletions = liveInvalidCompletions
        store = Store(initialState: state) {
            if observeLiveActivation {
                Reduce<CalendarFeature.State, CalendarFeature.Action> { state, action in
                    switch action {
                    case .refreshCalendarAuthorization:
                        refreshes.withValue { $0 += 1 }
                    case let .eventsLoaded(date, requestID, _), let .eventsFailed(date, requestID, _):
                        if refreshes.value > 0 {
                            if state.eventsRequestID == requestID && state.eventsDate == date {
                                completions.withValue { $0 += 1 }
                            } else {
                                invalidCompletions.withValue { $0 += 1 }
                            }
                        }
                    default: break
                    }
                    return .none
                }
            }
            CalendarFeature()
        } withDependencies: {
            $0.date = .constant(clockDate)
            $0.uuid = .init { UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)) }
            $0.calendarClient = .liveValue
            $0.calendarClient.menuBarDateString = { _, _ in
                effects.withValue { $0 += 1 }; Issue.record("Contrast fixture must not render a status item"); return ""
            }
            $0.preferencesClient = .testValue
            $0.preferencesClient.loadStartOfWeekday = { 1 }
            $0.preferencesClient.loadWorkdays = { [2, 3, 4, 5, 6] }
            $0.preferencesClient.loadShowAISearch = { true }
            $0.eventKitClient = EventKitClient(
                requestAccess: {
                    effects.withValue { $0 += 1 }; Issue.record("Contrast fixture must not request access"); return false
                },
                fetchEvents: { _ in
                    fetches.withValue { $0 += 1 }
                    entered.resolve(.success(()))
                    defer { returned.resolve(.success(())) }
                    if scenario == .selectedLoading { return try await release.wait() }
                    if scenario == .selectedQueryError { throw CalendarContrastFixtureFailure.syntheticQuery }
                    return events
                },
                authorizationStatus: { scenario.authorization }
            )
        }
        let resolutions = syntheticAIResolutions
        let calls = syntheticAICalls
        let aiRelease = aiRelease
        let model = AIDateQueryModel(
            client: AIDateQueryClient(
                resolveProvider: { _ in resolutions.withValue { $0 += 1 }; return .proxy },
                parseDate: { _, _ in
                    calls.withValue { $0 += 1 }
                    if scenario == .aiProcessing { try await aiRelease.wait() }
                    if scenario == .aiTransportError { throw AIDateFailure.transport }
                    if scenario == .aiUnavailable { throw AIDateFailure.unavailable }
                    return nil
                }
            ), enabled: true, preference: .auto,
            onDate: { _ in effects.withValue { $0 += 1 }; Issue.record("Error captures must not deliver an AI date") }
        )
        contrastModel = model
        let panel = CalendarPanel(
            contentRect: NSRect(x: -1000, y: -1000, width: 316, height: maximumHeight),
            caretOffset: 158, calendarStore: store, content: { _ in AnyView(EmptyView()) },
            capturePreviousApp: { nil },
            restorePreviousApp: { _ in effects.withValue { $0 += 1 }; Issue.record("Contrast capture must not restore another app") }
        )
        panel.isReleasedWhenClosed = false
        panel.isPinned = true
        panel.layoutState.updatePlacement(maximumHeight: maximumHeight, caretXOffset: 158)
        let calendarStore = store
        let hosting = NSHostingView(rootView: AnyView(
            CalendarPopoverView(
                store: calendarStore, panel: panel, layout: panel.layoutState,
                editorPresentation: { _ in }, aiQueryModel: model,
                loadAISettings: { (true, .auto) }, eventChangeNotificationCenter: NotificationCenter(),
                quitApplication: { effects.withValue { $0 += 1 }; Issue.record("Capture must not terminate the app") }
            ).environment(\.accessibilityEnabled, true)
        ))
        panel.contentView = hosting
        let screens = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        panel.setFrameOrigin(NSPoint(x: screens.minX - 1000, y: screens.minY - 1000))
        contrastPanel = panel
        contrastHosting = hosting
    }

    func mountContrast(dark: Bool?) async throws {
        let panel = try #require(contrastPanel)
        let hosting = try #require(contrastHosting)
        let scenario = try #require(contrastScenario)
        let model = try #require(contrastModel)
        if let dark {
            let appearance: NSAppearance.Name = dark ? .darkAqua : .aqua
            panel.appearance = try #require(NSAppearance(named: appearance))
            contrastAppearance = appearance
        } else {
            try #require(panel.appearance == nil, "System capture must inherit the native appearance")
        }
        panel.orderFront(nil)
        try await settleContrast(until: { self.store.days.count == 42 && panel.isVisible })
        if scenario.authorization == .fullAccess {
            try await fetchEntered.wait()
            try await settleContrast(until: {
                scenario == .selectedLoading ? self.store.isLoadingEvents : !self.store.isLoadingEvents
            })
        }
        model.setPanelVisible(panel.isVisible)
        if scenario.opensSearch {
            model.setEditorOpen(true)
            model.setDraft("Synthetic next Friday")
            if [.aiNoDate, .aiTransportError, .aiUnavailable, .aiProcessing].contains(scenario) {
                let task = try #require(model.submit())
                let receipt = AIDateIntegrationTrackedTask(task)
                aiReceipt = receipt
                if scenario == .aiProcessing {
                    try await settleContrast(until: { self.syntheticAICalls.value == 1 && model.isProcessing })
                } else { try await receipt.finish() }
            }
        }
        try await settleContrast()
        let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var windows: CFTypeRef?
        let axResult = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &windows)
        try #require(axResult == .success, "Owned contrast accessibility read returned \(axResult.rawValue)")
        try await settleContrast()
        if let dark {
            #expect(hosting.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == (dark ? .darkAqua : .aqua))
        } else {
            contrastAppearance = try #require(hosting.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]))
            #expect(panel.appearance == nil)
        }
        #expect(panel.contentView === hosting && panel.isPinned && store.isPinned)
    }

    func settleContrast(until predicate: () -> Bool = { true }) async throws {
        for _ in 0..<8 { contrastLayoutPass(); await Task.yield() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw CalendarContrastFixtureFailure.stateTimeout }
            contrastLayoutPass()
            await Task.yield()
        }
    }

    private func contrastLayoutPass() {
        guard let hosting = contrastHosting, let panel = contrastPanel else { return }
        let fitting = hosting.fittingSize
        if fitting.width.isFinite && fitting.height.isFinite && fitting.width > 0 && fitting.height > 0 {
            let actual = panel.contentRect(forFrameRect: panel.frame).size
            if abs(actual.width - fitting.width) > 0.5 || abs(actual.height - fitting.height) > 0.5 {
                panel.setContentSize(fitting)
            }
        }
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        CFRunLoopRunInMode(.defaultMode, 0.01, true)
    }

    func contrastNodes() -> [AccessibilityTestNode] {
        guard let hosting = contrastHosting else { return [] }
        var queue: [Any] = [hosting]
        var visited: Set<ObjectIdentifier> = []
        var nodes: [AccessibilityTestNode] = []
        var index = 0
        while index < queue.count && index < 2048 {
            let object = queue[index] as AnyObject
            index += 1
            guard object.responds?(to: #selector(NSAccessibilityProtocol.accessibilityRole)) == true,
                  visited.insert(ObjectIdentifier(object)).inserted else { continue }
            let node = AccessibilityTestNode(object: object)
            nodes.append(node)
            queue.append(contentsOf: node.children + node.contents + node.visibleChildren)
        }
        #expect(index == queue.count, "Owned contrast accessibility tree must fit its explicit bound")
        return nodes
    }

    func expectContrastState(afterOwnedActivation: Bool = false) throws {
        let scenario = try #require(contrastScenario)
        let model = try #require(contrastModel)
        let nodes = contrastNodes()
        @MainActor
        func has(_ text: String) -> Bool {
            nodes.contains { $0.label == text || ($0.value as? String) == text }
        }
        #expect(store.days.count == 42 && store.selectedDate == expectedSelection)
        #expect(store.calendarAuthorizationStatus == scenario.authorization)
        if afterOwnedActivation {
            #expect(syntheticFetches.value == (scenario.authorization == .fullAccess ? 2 : 0))
        } else {
            #expect(syntheticFetches.value == (scenario.authorization == .fullAccess ? 1 : 0))
        }
        #expect(protectedEffects.value == 0)
        switch scenario {
        case .selectedLoading: #expect(store.isLoadingEvents && has("Loading events…"))
        case .selectedQueryError:
            #expect(store.eventsError != nil && has("Couldn’t load events."))
            #expect(nodes.contains { $0.label == "Retry loading calendar events" && $0.role == .button })
        case .selectedResult, .multipleEvents:
            #expect(store.events == expectedEvents)
            #expect(expectedEvents.prefix(5).allSatisfy { has("\($0.title), \($0.timeString)") })
            if scenario == .multipleEvents {
                #expect(has("+2 more") && !has("\(expectedEvents[5].title), \(expectedEvents[5].timeString)"))
            }
        case .accessNotDetermined: #expect(has("Grant calendar access to show events"))
        case .accessDenied: #expect(has("Calendar access is off."))
        case .accessRestricted: #expect(has("Calendar access is restricted on this Mac."))
        case .accessWriteOnly: #expect(has("Allow full calendar access to read events."))
        case .accessRequesting: #expect(store.isRequestingCalendarAccess && has("Requesting calendar access…"))
        case .accessError: #expect(has("Calendar access is off.") && has("Synthetic calendar access failed."))
        case .aiNoDate:
            #expect(model.errorMessage == "AI didn't return a usable date. Try ‘next Friday’ or ‘Jan 2028’.")
        case .aiTransportError: #expect(model.errorMessage == "AI couldn't complete the date search. Try again.")
        case .aiUnavailable: #expect(model.errorMessage == "On-device AI is unavailable. Choose Cloud AI in Preferences.")
        case .aiProcessing: #expect(model.isProcessing && model.errorMessage == nil)
        default: #expect(has("No events") && store.events.isEmpty)
        }
        if let error = model.errorMessage { #expect(has(error)) }
        #expect(model.isEditorOpen == scenario.opensSearch)
        let submits = [.aiNoDate, .aiTransportError, .aiUnavailable, .aiProcessing].contains(scenario) ? 1 : 0
        #expect(syntheticAICalls.value == submits && syntheticAIResolutions.value == submits)
        if scenario == .noSelectionToday || scenario == .selectedToday {
            let day = try #require(store.eventsDate)
            #expect(Calendar.current.isDateInToday(day))
        }
        let dateLabels = store.days.map {
            $0.date.formatted(Date.FormatStyle.dateTime.weekday(.wide).month(.wide).day().year())
        }
        let dates = nodes.filter { node in
            node.role == .button && dateLabels.contains { node.label?.hasPrefix($0) == true }
        }
        #expect(dates.count == 42 && Set(dates.compactMap(\.label)).count == 42)
        #expect(dates.allSatisfy { $0.enabled && abs($0.frame.height - 30) < 0.5 && $0.frame.width > 28 })
        #expect(dates.contains { $0.label?.contains("outside current month") == true })
        #expect(dates.filter(\.selected).count == (expectedSelection == nil ? 0 : 1))
        #expect(nodes.filter { $0.label?.hasPrefix("Calendar events for ") == true }.count == 1)
        #expect(has("Wk"))
    }

    func revealContrastRole(_ node: AccessibilityTestNode) async throws {
        let panel = try #require(contrastPanel)
        let hosting = try #require(contrastHosting)
        let scroll = try #require(accessibilityScrollView(in: hosting))
        let document = try #require(scroll.documentView)
        let originalFrame = panel.frame
        let originalX = scroll.contentView.bounds.origin.x
        let originalMonth = store.displayedMonth
        let originalSelection = store.selectedDate
        let originalPin = store.isPinned
        let frame = node.frame
        try #require(frame.minX.isFinite && frame.minY.isFinite && frame.width.isFinite
                     && frame.height.isFinite && frame.width > 0 && frame.height > 0)
        try #require(node.object.accessibilityWindow?() as? NSWindow === panel)
        let inDocument = document.convert(panel.convertFromScreen(frame), from: nil)
        _ = document.scrollToVisible(inDocument.insetBy(dx: -4, dy: -4))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await settleContrast()
        let actualFrame = node.frame
        let inClip = scroll.contentView.convert(panel.convertFromScreen(actualFrame), from: nil)
        #expect(scroll.contentView.bounds.contains(inClip))
        #expect(panel.frame == originalFrame && scroll.contentView.bounds.origin.x == originalX)
        #expect(panel.contentView === hosting && scroll.documentView === document)
        #expect(store.displayedMonth == originalMonth && store.selectedDate == originalSelection
                && store.isPinned == originalPin && panel.isPinned == originalPin)
        if let scroller = scroll.verticalScroller, !scroller.isHidden {
            let scrollerFrame = panel.convertToScreen(scroller.convert(scroller.bounds, to: nil))
            #expect(!scrollerFrame.intersects(actualFrame))
        }
        #expect(protectedEffects.value == 0)
    }

    func revealContrastFooter() async throws {
        for name in ["Quit Glimpse", "About Glimpse", "Unpin calendar window", "Open Calendar app", "Open Glimpse Settings"] {
            let node = try #require(contrastNodes().first { $0.label == name && $0.role == .button })
            try await revealContrastRole(node)
        }
    }

    func captureContrastState(_ phase: String) throws {
        let panel = try #require(contrastPanel)
        let hosting = try #require(contrastHosting)
        let scenario = try #require(contrastScenario)
        let appearance = try #require(contrastAppearance)
        try #require(hosting.bounds.width.isFinite && hosting.bounds.height.isFinite
                     && hosting.bounds.width > 0 && hosting.bounds.height > 0)
        let path = try #require(ProcessInfo.processInfo.environment["GLIMPSE_CONTRAST_ARTIFACT_DIR"],
                                "Contrast capture acceptance requires its explicit owned artifact destination")
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let theme = appearance == .darkAqua ? "dark" : "light"
        let name = "\(scenario.rawValue)-\(theme)-\(Int(panel.layoutState.maximumHeight))-\(phase)"
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let output = directory.appendingPathComponent(name + ".png")
        try #require(!FileManager.default.fileExists(atPath: output.path))
        try png.write(to: output)
        try #require(bitmap.pixelsWide > 2 && bitmap.pixelsHigh > 2)
        let caretX = min(bitmap.pixelsWide - 1, max(0, Int(
            panel.caretXOffset / hosting.bounds.width * CGFloat(bitmap.pixelsWide)
        )))
        let caretY = min(bitmap.pixelsHigh - 1, max(0, Int(
            3 / hosting.bounds.height * CGFloat(bitmap.pixelsHigh)
        )))
        let samples: [[String: Any]] = [
            ("corner-0-0", 0, 0), ("corner-right-0", bitmap.pixelsWide - 1, 0),
            ("corner-0-last", 0, bitmap.pixelsHigh - 1),
            ("corner-right-last", bitmap.pixelsWide - 1, bitmap.pixelsHigh - 1),
            ("center", bitmap.pixelsWide / 2, bitmap.pixelsHigh / 2),
            ("caret-candidate-first-rows", caretX, caretY),
            ("caret-candidate-last-rows", caretX, bitmap.pixelsHigh - 1 - caretY)
        ].map { name, x, y in
            let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
            return ["name": name, "pixel": [x, y],
                    "rgba": color.map { [$0.redComponent, $0.greenComponent, $0.blueComponent, $0.alphaComponent] } ?? [],
                    "qualification": "Raw bitmap coordinate; confirm caret/body orientation and avoid glyph/stroke before seam/opacity judgment"]
        }
        let scroll = try #require(accessibilityScrollView(in: hosting))
        let nodes = contrastNodes()
        try #require(nodes.count <= 512, "Metadata must retain every owned node without truncating roles")
        let rows: [[String: Any]] = nodes.map { node in
            let frame = hosting.convert(panel.convertFromScreen(node.frame), from: nil)
            return [
                "role": node.role?.rawValue ?? "", "class": String(describing: type(of: node.object)),
                "label": String((node.label ?? "").prefix(200)),
                "value": String(((node.value as? String) ?? "").prefix(200)),
                "valueDescription": String((node.object.accessibilityValueDescription?() ?? "").prefix(200)),
                "frameInHosting": NSStringFromRect(frame), "enabled": node.enabled, "selected": node.selected,
                "windowOwned": node.object.accessibilityWindow?() as? NSWindow === panel,
                "roiQualification": "Native element/group bounds; isolate glyphs separately before per-role contrast measurement"
            ]
        }
        let metadata: [String: Any] = [
            "source": "Glimpse/CalendarPopoverView.swift", "testSource": #filePath,
            "scenario": scenario.rawValue, "phase": phase,
            "requestedAppearance": panel.appearance == nil ? NSNull() : appearance.rawValue as Any,
            "effectiveAppearance": hosting.effectiveAppearance.name.rawValue,
            "windowFrame": NSStringFromRect(panel.frame), "hostingBounds": NSStringFromRect(hosting.bounds),
            "clipBounds": NSStringFromRect(scroll.contentView.bounds),
            "documentBounds": NSStringFromRect(scroll.documentView?.bounds ?? .zero),
            "caretOffset": panel.caretXOffset, "backingScale": panel.backingScaleFactor,
            "bitmapPixels": [bitmap.pixelsWide, bitmap.pixelsHigh], "bitmapHasAlpha": bitmap.hasAlpha,
            "rawBitmapSamples": samples, "hostingIsFlipped": hosting.isFlipped,
            "bodyFrameInHosting": NSStringFromRect(hosting.convert(scroll.bounds, from: scroll)),
            "displayedMonth": store.displayedMonth.timeIntervalSince1970,
            "selectedDate": store.selectedDate.map { $0.timeIntervalSince1970 as Any } ?? NSNull(),
            "events": expectedEvents.map {
                ["title": $0.title, "time": $0.timeString, "allDay": $0.isAllDay] as [String: Any]
            },
            "pinned": panel.isPinned, "calendarKey": panel.isKeyWindow, "appActive": NSApp.isActive,
            "syntheticFetches": syntheticFetches.value, "syntheticAI": syntheticAICalls.value,
            "syntheticProviderResolutions": syntheticAIResolutions.value,
            "protectedEffects": protectedEffects.value, "nodes": rows,
            "appearanceScope": panel.appearance == nil
                ? "Inherited OS appearance, accessibilityEnabled fixture injection"
                : "Owned window-local appearance, accessibilityEnabled fixture injection",
            "environmentScope": "No Reduce Transparency, Increase Contrast or accent override; no global-setting change",
            "backdropScope": panel.appearance == nil
                ? "Hosting bitmap of an onscreen synthetic panel; not a compositor capture"
                : "Offscreen hosting bitmap; excludes actual desktop and surrounding applications",
            "unperformed": ["system Reduce Transparency/Increase Contrast", "desktop backdrops", "user accent changes",
                            "installed appearance", "private KVO/anchor resize", "per-glyph contrast and alpha-region sampling"]
        ]
        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys, .prettyPrinted])
        let sidecar = directory.appendingPathComponent(name + ".json")
        try #require(!FileManager.default.fileExists(atPath: sidecar.path))
        try data.write(to: sidecar)
        #expect(protectedEffects.value == 0)
        print("GLIMPSE_CONTRAST_CAPTURE bitmap=\(output.path) metadata=\(sidecar.path)")
    }

    func drainContrastWork() async throws {
        let cleanup = Task { @MainActor in
            var failure: (any Error)?
            // Admit the real fake-client entry before cancellation, including a
            // failed mount. A missing entry is a bounded failure, never a join claim.
            if self.contrastScenario?.authorization == .fullAccess {
                do { try await self.fetchEntered.wait() } catch { failure = error }
            }
            self.contrastModel?.setPanelVisible(false)
            self.store.send(.closePanel)
            self.fetchRelease.resolve(.success([]))
            self.aiRelease.resolve(.success(()))
            defer {
                self.contrastPanel?.orderOut(nil)
                self.contrastHosting?.rootView = AnyView(EmptyView())
                self.contrastPanel?.contentView = nil
                self.contrastPanel?.close()
            }
            if let receipt = self.aiReceipt {
                do { try await receipt.finish() } catch { if failure == nil { failure = error } }
            }
            if self.syntheticFetches.value > 0 {
                do { try await self.fetchReturned.wait() } catch { if failure == nil { failure = error } }
            }
            for signal in [self.fetchEntered, self.fetchReturned, self.aiRelease] { await signal.drainWatchdogs() }
            await self.fetchRelease.drainWatchdogs()
            #expect(self.protectedEffects.value == 0)
            if let failure { throw failure }
        }
        try await cleanup.value
    }
}

@MainActor
func accessibilityScrollView(in view: NSView) -> NSScrollView? {
    if let scroll = view as? NSScrollView { return scroll }
    for child in view.subviews {
        if let scroll = accessibilityScrollView(in: child) { return scroll }
    }
    return nil
}

@MainActor
func viewportBodyScreenRect(
    host: AccessibilityTestHost, scroll: NSScrollView, layout: PanelLayoutState
) -> NSRect {
    var body = scroll.convert(scroll.bounds, to: host.hosting)
    body.size = NSSize(width: PanelGeometry.contentWidth, height: layout.viewportHeight)
    return host.window.convertToScreen(host.hosting.convert(body, to: nil))
}
