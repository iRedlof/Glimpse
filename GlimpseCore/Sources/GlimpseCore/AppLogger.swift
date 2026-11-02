import os

/// Core clients cannot depend on the app target; use the same logging subsystem
/// so diagnostics include client and reducer failures alongside AppKit events.
enum AppLogger {
    static let preferences = Logger(subsystem: "com.rohit.Glimpse", category: "preferences")
    static let calendar = Logger(subsystem: "com.rohit.Glimpse", category: "calendar")
}
