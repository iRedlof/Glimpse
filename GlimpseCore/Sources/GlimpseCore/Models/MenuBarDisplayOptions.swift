import Foundation

public struct MenuBarDisplayOptions: Equatable, Sendable, Codable {
    public var showIcon: Bool
    public var showDayOfWeek: Bool
    public var showMonth: Bool
    public var showDate: Bool
    public var showYear: Bool
    public var showFilledBackground: Bool
    /// Opt-in: append today's next meeting ("Standup in 12m") to the item.
    public var showNextMeeting: Bool
    /// Opt-in: "Dentist · leave by 8:40" in the menu bar and a "Leave by" agenda chip.
    public var showLeaveBy: Bool
    /// Minutes before a located event's start to leave; one of `LeaveBy.bufferChoices`.
    public var leaveByMinutes: Int

    public static let `default` = MenuBarDisplayOptions(
        showIcon: true,
        showDayOfWeek: true,
        showMonth: true,
        showDate: true,
        showYear: false,
        showFilledBackground: false,
        showNextMeeting: false,
        showLeaveBy: false,
        leaveByMinutes: LeaveBy.defaultBufferMinutes
    )

    public init(
        showIcon: Bool = true,
        showDayOfWeek: Bool = true,
        showMonth: Bool = true,
        showDate: Bool = true,
        showYear: Bool = false,
        showFilledBackground: Bool = false,
        showNextMeeting: Bool = false,
        showLeaveBy: Bool = false,
        leaveByMinutes: Int = LeaveBy.defaultBufferMinutes
    ) {
        self.showIcon = showIcon
        self.showDayOfWeek = showDayOfWeek
        self.showMonth = showMonth
        self.showDate = showDate
        self.showYear = showYear
        self.showFilledBackground = showFilledBackground
        self.showNextMeeting = showNextMeeting
        self.showLeaveBy = showLeaveBy
        self.leaveByMinutes = LeaveBy.validatedBuffer(leaveByMinutes)
    }

    /// The buffer when leave-by is on, else nil.
    public var activeLeaveByMinutes: Int? { showLeaveBy ? leaveByMinutes : nil }

    private enum CodingKeys: String, CodingKey {
        case showIcon, showDayOfWeek, showMonth, showDate, showYear, showFilledBackground, showNextMeeting
        case showLeaveBy, leaveByMinutes
    }

    /// Missing keys (older encodings) fall back to the defaults.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self.default
        func value(_ key: CodingKeys, _ defaultValue: Bool) throws -> Bool {
            try container.decodeIfPresent(Bool.self, forKey: key) ?? defaultValue
        }
        self.init(
            showIcon: try value(.showIcon, fallback.showIcon),
            showDayOfWeek: try value(.showDayOfWeek, fallback.showDayOfWeek),
            showMonth: try value(.showMonth, fallback.showMonth),
            showDate: try value(.showDate, fallback.showDate),
            showYear: try value(.showYear, fallback.showYear),
            showFilledBackground: try value(.showFilledBackground, fallback.showFilledBackground),
            showNextMeeting: try value(.showNextMeeting, fallback.showNextMeeting),
            showLeaveBy: try value(.showLeaveBy, fallback.showLeaveBy),
            leaveByMinutes: try container.decodeIfPresent(Int.self, forKey: .leaveByMinutes) ?? fallback.leaveByMinutes
        )
    }
}
