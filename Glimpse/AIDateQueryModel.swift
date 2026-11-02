import Foundation
import GlimpseCore
import Observation

/// Owns one search in the current visible editor. Setters relinquish ownership
/// synchronously, so a cancellation-ignoring provider cannot publish stale work.
@MainActor
@Observable
final class AIDateQueryModel {
    private(set) var draft = ""
    private(set) var isEditorOpen = false
    private(set) var isProcessing = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let client: AIDateQueryClient
    @ObservationIgnored private let onDate: @MainActor (Date) -> Void
    @ObservationIgnored private var enabled: Bool
    @ObservationIgnored private var preference: AIProvider
    @ObservationIgnored private var panelVisible = false
    @ObservationIgnored private var requestTask: Task<Void, Never>?
    @ObservationIgnored private var requestToken: RequestToken?
    @ObservationIgnored private var editorGeneration: UInt64 = 0
    @ObservationIgnored private var draftRevision: UInt64 = 0
    @ObservationIgnored private var preferenceRevision: UInt64 = 0

    var currentRequestID: UUID? { requestToken?.id }

    private struct RequestToken: Equatable, Sendable {
        let id: UUID
        let editorGeneration: UInt64
        let draftRevision: UInt64
        let preferenceRevision: UInt64
        let provider: AIDateHelper.Provider
    }

    private enum Outcome {
        case date(Date), noDate, failure, unavailable, cancelled
    }

    init(
        client: AIDateQueryClient,
        enabled: Bool,
        preference: AIProvider,
        onDate: @escaping @MainActor (Date) -> Void
    ) {
        self.client = client
        self.enabled = enabled
        self.preference = preference
        self.onDate = onDate
    }

    func setDraft(_ draft: String) {
        guard self.draft != draft else { return }
        draftRevision &+= 1
        self.draft = draft
        abandonRequest()
    }

    func setEditorOpen(_ open: Bool) {
        guard open else {
            discardEditor()
            return
        }
        guard !isEditorOpen else { return }
        editorGeneration &+= 1
        isEditorOpen = true
        errorMessage = nil
    }

    func setPanelVisible(_ visible: Bool) {
        guard panelVisible != visible else { return }
        panelVisible = visible
        if !visible { discardEditor() }
    }

    func synchronizeSettings(enabled: Bool, preference: AIProvider) {
        let providerChanged = self.preference != preference
        if providerChanged { preferenceRevision &+= 1 }
        self.enabled = enabled
        self.preference = preference
        if !enabled { discardEditor() }
        else if providerChanged { abandonRequest() }
    }

    func discardEditor() {
        editorGeneration &+= 1
        draftRevision &+= 1
        isEditorOpen = false
        draft = ""
        abandonRequest()
    }

    private func abandonRequest() {
        let abandonedTask = requestTask
        requestToken = nil
        requestTask = nil
        isProcessing = false
        errorMessage = nil
        // A registered cancellation handler can run synchronously here. It must
        // already see the request as relinquished, including its progress/error.
        abandonedTask?.cancel()
    }

    @discardableResult
    func submit() -> Task<Void, Never>? {
        let query = draft.trimmingCharacters(in: .whitespaces)
        guard panelVisible, enabled, isEditorOpen, !query.isEmpty,
              requestToken == nil else { return nil }
        let token = RequestToken(
            id: UUID(), editorGeneration: editorGeneration,
            draftRevision: draftRevision, preferenceRevision: preferenceRevision,
            provider: client.resolveProvider(preference)
        )
        requestToken = token
        isProcessing = true
        errorMessage = nil

        let client = client
        let task = Task { @MainActor [weak self] in
            let outcome: Outcome
            do {
                try Task.checkCancellation()
                let date = try await client.parseDate(query, token.provider)
                try Task.checkCancellation()
                if let date { outcome = .date(date) }
                else { outcome = .noDate }
            } catch is CancellationError {
                outcome = .cancelled
            } catch {
                // Error payloads never enter observable state or logs.
                outcome = Task.isCancelled ? .cancelled
                    : (error as? AIDateFailure == .unavailable ? .unavailable : .failure)
            }
            self?.complete(outcome, token: token)
        }
        requestTask = task
        return task
    }

    private func complete(_ outcome: Outcome, token: RequestToken) {
        guard requestToken == token,
              editorGeneration == token.editorGeneration,
              draftRevision == token.draftRevision,
              preferenceRevision == token.preferenceRevision,
              panelVisible, enabled, isEditorOpen else { return }

        let currentOutcome: Outcome = Task.isCancelled ? .cancelled : outcome
        requestToken = nil
        requestTask = nil
        isProcessing = false
        errorMessage = nil
        switch currentOutcome {
        case .date(let date):
            draftRevision &+= 1
            editorGeneration &+= 1
            draft = ""
            isEditorOpen = false
            // All old ownership is cleared before the consumer can synchronously
            // open and submit a new editor. Do not clean up again after this call.
            onDate(date)
        case .noDate:
            errorMessage = "AI didn't return a usable date. Try ‘next Friday’ or ‘Jan 2028’."
        case .failure:
            errorMessage = "AI couldn't complete the date search. Try again."
        case .unavailable:
            errorMessage = "On-device AI is unavailable. Choose Cloud AI in Preferences."
        case .cancelled:
            break
        }
    }
}
