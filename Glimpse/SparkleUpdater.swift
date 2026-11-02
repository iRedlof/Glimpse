import AppKit
import Combine
import Sparkle
import SwiftUI

// MARK: - Update Status

enum UpdateFailure: Equatable {
    case check
    case update
}

enum UpdateStatus: Equatable {
    case idle
    case initializationFailed
    case checking
    case latest
    case error(UpdateFailure)
    case available(version: String)
    case downloading
    case extracting
    case readyToInstall
}

@MainActor
struct UpdaterClient {
    var start: () throws -> Void
    var canCheckForUpdates: () -> Bool
    var observeCanCheckForUpdates: (@escaping @MainActor (Bool) -> Void) -> AnyCancellable
    var checkForUpdates: () -> Void

    static func live(userDriver: InlineUpdateDriver) -> Self {
        let updater = SPUUpdater(
            hostBundle: Bundle.main,
            applicationBundle: Bundle.main,
            userDriver: userDriver,
            delegate: nil
        )
        return Self(
            start: { try updater.start() },
            canCheckForUpdates: { updater.canCheckForUpdates },
            observeCanCheckForUpdates: { receive in
                updater.publisher(for: \.canCheckForUpdates).sink { receive($0) }
            },
            checkForUpdates: { updater.checkForUpdates() }
        )
    }
}

// MARK: - Sparkle Updater (shared)

@Observable
@MainActor
final class SparkleUpdater {
    static let shared = SparkleUpdater()

    let userDriver: InlineUpdateDriver
    private let client: UpdaterClient
    private var initializationSucceeded = false
    private var observedCanCheckForUpdates = false
    private var cancellable: AnyCancellable?

    var canCheckForUpdates: Bool {
        guard initializationSucceeded, observedCanCheckForUpdates,
              userDriver.updateChoiceID == nil, userDriver.installChoiceID == nil
        else { return false }
        switch userDriver.status {
        case .idle, .error:
            return true
        default:
            return false
        }
    }

    var availableVersion: String? {
        if case .available(let version) = userDriver.status { return version }
        return nil
    }

    private convenience init() {
        let driver = InlineUpdateDriver()
        self.init(userDriver: driver, client: .live(userDriver: driver))
    }

    init(userDriver: InlineUpdateDriver, client: UpdaterClient) {
        self.userDriver = userDriver
        self.client = client
        cancellable = client.observeCanCheckForUpdates { [weak self] in
            self?.observedCanCheckForUpdates = $0
        }
        do {
            try client.start()
            initializationSucceeded = true
            AppLogger.general.info("Sparkle updater started")
        } catch {
            userDriver.showInitializationFailure()
            AppLogger.general.error("Sparkle initialization failed (code \((error as NSError).code))")
        }
    }

    func checkForUpdates() {
        observedCanCheckForUpdates = client.canCheckForUpdates()
        guard canCheckForUpdates else { return }
        userDriver.beginUserInitiatedCheck()
        client.checkForUpdates()
    }
}

// MARK: - Inline User Driver

@Observable
@MainActor
final class InlineUpdateDriver: NSObject, SPUUserDriver {
    var status: UpdateStatus = .idle
    private var pendingReply: ((SPUUserUpdateChoice) -> Void)?
    private var pendingInstallReply: ((SPUUserUpdateChoice) -> Void)?
    private(set) var updateChoiceID: UUID?
    private(set) var installChoiceID: UUID?
    private var dismissTask: Task<Void, Never>?
    private let delay: @MainActor (Duration) async throws -> Void
    private static let latestDismissDelay: Duration = .seconds(5)

    init(delay: @escaping @MainActor (Duration) async throws -> Void = {
        try await Task.sleep(for: $0)
    }) {
        self.delay = delay
        super.init()
    }

    func beginUserInitiatedCheck() {
        publish(.checking)
    }

    func showInitializationFailure() {
        publish(.initializationFailed)
    }

    private func publish(_ nextStatus: UpdateStatus) {
        dismissTask?.cancel()
        dismissTask = nil
        status = nextStatus
    }

    private func scheduleLatestDismissal() {
        let delay = self.delay
        dismissTask = Task { @MainActor [weak self] in
            do {
                try await delay(Self.latestDismissDelay)
            } catch is CancellationError {
                return
            } catch {
                AppLogger.general.error("Update result delay failed (code \((error as NSError).code))")
                return
            }
            guard !Task.isCancelled, let self, self.status == .latest else { return }
            self.dismissTask = nil
            self.status = .idle
        }
    }

    // MARK: - SPUUserDriver

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        beginUserInitiatedCheck()
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping @Sendable (SPUUserUpdateChoice) -> Void) {
        let version = appcastItem.displayVersionString ?? appcastItem.versionString
        presentUpdate(version: version, reply: reply)
    }

    func presentUpdate(version: String, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        pendingReply = reply
        updateChoiceID = UUID()
        publish(.available(version: version))
    }

    func chooseUpdate(_ choice: SPUUserUpdateChoice, id: UUID) {
        guard case .available = status, updateChoiceID == id,
              choice == .install || choice == .skip,
              let reply = pendingReply
        else { return }
        pendingReply = nil
        updateChoiceID = nil
        reply(choice)
    }

    func chooseInstallAndRelaunch(id: UUID) {
        guard status == .readyToInstall, installChoiceID == id,
              let reply = pendingInstallReply
        else { return }
        pendingInstallReply = nil
        installChoiceID = nil
        reply(.install)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        publish(.latest)
        scheduleLatestDismissal()
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        let failure: UpdateFailure = status == .checking ? .check : .update
        publish(.error(failure))
        AppLogger.general.error("Sparkle update failed (code \((error as NSError).code))")
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        publish(.downloading)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}

    func showDownloadDidStartExtractingUpdate() {
        publish(.extracting)
    }

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        pendingInstallReply = reply
        installChoiceID = UUID()
        publish(.readyToInstall)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        publish(.extracting)
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        dismissUpdateInstallation()
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        pendingReply = nil
        pendingInstallReply = nil
        updateChoiceID = nil
        installChoiceID = nil
        switch status {
        case .initializationFailed, .error, .latest:
            break
        default:
            publish(.idle)
        }
    }
}
