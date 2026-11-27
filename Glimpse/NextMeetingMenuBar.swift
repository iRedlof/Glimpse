import AppKit
import Combine
import ComposableArchitecture
import EventKit
import GlimpseCore
import Observation

/// The opt-in next-meeting segment drawn after the date ("Standup in 12m").
struct MenuBarMeetingSegment: Equatable {
    let text: String
    /// Starts within five minutes: the whole pill turns amber.
    let isImminent: Bool

    init(text: String, isImminent: Bool) {
        self.text = text
        self.isImminent = isImminent
    }

    init(_ meeting: NextMeeting, calendar: Calendar = .autoupdatingCurrent,
         locale: Locale = .autoupdatingCurrent) {
        self.init(text: NextMeetingText.menuBarText(for: meeting, calendar: calendar, locale: locale),
                  isImminent: meeting.isImminent)
    }

    /// Settings preview when no meeting is live, so the toggle shows what it adds.
    static let previewSample = MenuBarMeetingSegment(text: "Standup in 12m", isImminent: false)
    /// The preview sample with leave-by on: a located event reads "leave by".
    static let leaveByPreviewSample = MenuBarMeetingSegment(text: "Dentist · leave by 8:40", isImminent: false)
}

/// Bridges `NextMeetingFeature` to the AppKit status item.
///
/// The status item stays the only owner of `button.image`: this controller only
/// publishes `segment` and calls `onChange`; it never touches the button, never
/// observes appearance, and never adds views. EventKit changes are debounced so a
/// sync burst costs one query.
@MainActor
@Observable
final class NextMeetingMenuBarController {
    static let shared = NextMeetingMenuBarController()
    /// Calendar syncs post bursts of change notifications; one query per burst.
    static let changeDebounce: DispatchQueue.SchedulerTimeType.Stride = .milliseconds(500)

    /// The live segment, or nil when off, without access, or after the last meeting.
    private(set) var segment: MenuBarMeetingSegment?
    @ObservationIgnored var onChange: (@MainActor () -> Void)?
    @ObservationIgnored private let store: StoreOf<NextMeetingFeature>
    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []

    init(store: StoreOf<NextMeetingFeature> = Store(initialState: NextMeetingFeature.State()) {
        NextMeetingFeature()
    }, notificationCenter: NotificationCenter = .default) {
        self.store = store
        store.publisher.meeting
            .removeDuplicates()
            .sink { [weak self] meeting in
                // StorePublisher delivers on the main thread (the store's thread).
                MainActor.assumeIsolated { self?.apply(meeting) }
            }
            .store(in: &cancellables)
        notificationCenter.publisher(for: .EKEventStoreChanged)
            .debounce(for: Self.changeDebounce, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    store.send(.calendarChanged)
                }
            }
            .store(in: &cancellables)
        notificationCenter.publisher(for: .NSSystemTimeZoneDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            .store(in: &cancellables)
    }

    var isEnabled: Bool { store.isEnabled }

    func setEnabled(_ enabled: Bool) {
        store.send(.setEnabled(enabled))
    }

    /// Applies the saved menu bar options: the segment toggle and the leave-by buffer.
    func apply(_ options: MenuBarDisplayOptions) {
        store.send(.setLeaveBy(minutes: options.activeLeaveByMinutes))
        store.send(.setEnabled(options.showNextMeeting))
    }

    var leaveByMinutes: Int? { store.leaveByMinutes }

    /// Re-read today's events (wake, midnight, clock change, panel closed).
    func refresh() {
        store.send(.refresh)
    }

    private func apply(_ meeting: NextMeeting?) {
        let next = meeting.map { MenuBarMeetingSegment($0) }
        guard next != segment else { return }
        segment = next
        onChange?()
    }
}
