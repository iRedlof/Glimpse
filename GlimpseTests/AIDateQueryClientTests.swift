import ComposableArchitecture
import Foundation
import GlimpseCore
import Testing
@testable import Glimpse

struct AIDateQueryClientTests {
    enum CompletedResponse: String, CaseIterable, Sendable {
        case json, fenced, create, legacyISO, legacyWhitespaceISO, prose, embedded, empty, whitespaceOnly

        var text: String {
            switch self {
            case .json: #"{"intent":"navigate","date":"2026-03-15"}"#
            case .fenced: "Here you go:\n```json\n{\"intent\":\"range\",\"dates\":[\"2026-03-20\",\"2026-03-13\"],\"label\":\"Fridays\"}\n```"
            case .create: #"{"intent":"create","title":"Coffee","date":"2026-03-15","partOfDay":"afternoon"}"#
            case .legacyISO: "2026-03-15"
            case .legacyWhitespaceISO: "  2026-01-01  \n"
            case .prose: "not a date at all"
            case .embedded: "The date is 2026-12-25 for Christmas"
            case .empty: ""
            case .whitespaceOnly: " \n\t "
            }
        }

        var expectedIntent: AIIntent? {
            switch self {
            case .json, .legacyISO: .navigate(CivilDate(year: 2026, month: 3, day: 15)!)
            case .legacyWhitespaceISO: .navigate(CivilDate(year: 2026, month: 1, day: 1)!)
            case .fenced: .range(DateRangeHighlight(
                dates: [CivilDate(year: 2026, month: 3, day: 13)!, CivilDate(year: 2026, month: 3, day: 20)!],
                label: "Fridays"
            ))
            case .create: .create(EventDraft(
                title: "Coffee", day: CivilDate(year: 2026, month: 3, day: 15)!,
                window: .partOfDay(.afternoon), durationMinutes: 30
            ))
            case .prose, .embedded, .empty, .whitespaceOnly: nil
            }
        }
    }

    enum FailedResponse: String, CaseIterable, Sendable {
        case nonHTTP, badRequest, serverError, malformedJSON
        case arrayJSON, missingText, nullText, numericText, upstreamError

        var expectedFailure: AIDateFailure {
            switch self {
            case .nonHTTP: .nonHTTPResponse
            case .badRequest, .serverError: .nonSuccessResponse
            case .malformedJSON, .arrayJSON, .missingText, .nullText, .numericText, .upstreamError:
                .unusableResponse
            }
        }

        func response() -> (Data, URLResponse) {
            let data: Data
            switch self {
            case .malformedJSON: data = Data(SelfHostileError.marker.utf8)
            case .arrayJSON: data = Data("[]".utf8)
            case .missingText: data = Data("{}".utf8)
            case .nullText: data = Data("{\"text\":null}".utf8)
            case .numericText: data = Data("{\"text\":42}".utf8)
            case .upstreamError:
                // Observed live on 2026-11-08: HTTP 200 with a null text and an upstream error.
                data = Data("{\"text\":null,\"model\":\"m\",\"error\":\"Upstream error: 401\"}".utf8)
            default: data = Data("{\"text\":\"2026-03-15\"}".utf8)
            }
            if self == .nonHTTP {
                return (data, URLResponse(
                    url: AIDateQueryClientTests.endpoint,
                    mimeType: "application/json", expectedContentLength: data.count,
                    textEncodingName: nil
                ))
            }
            let status = self == .badRequest ? 400 : self == .serverError ? 500 : 200
            return (data, AIDateQueryClientTests.httpResponse(status: status))
        }
    }

    @Test(arguments: CompletedResponse.allCases)
    func proxyIntentAndCompletedUnparsed(response: CompletedResponse) async throws {
        let authorizationCalls = LockIsolated(0)
        let transportCalls = LockIsolated(0)
        let requestContractMatched = LockIsolated(false)
        let data = try JSONSerialization.data(withJSONObject: ["text": response.text])
        let dependencies = ProxyProvider.Dependencies(
            endpoint: Self.endpoint.absoluteString,
            authorize: { request in
                authorizationCalls.withValue { $0 += 1 }
                request.setValue("synthetic-token", forHTTPHeaderField: "X-Fixture-Authorization")
            },
            now: { Self.now },
            calendar: Self.calendar,
            transport: { request in
                transportCalls.withValue { $0 += 1 }
                let body = request.httpBody.flatMap {
                    (try? JSONSerialization.jsonObject(with: $0)) as? [String: String]
                }
                requestContractMatched.setValue(
                    request.url == Self.endpoint
                        && request.httpMethod == "POST"
                        && request.timeoutInterval == 15
                        && request.value(forHTTPHeaderField: "Content-Type") == "application/json"
                        && request.value(forHTTPHeaderField: "X-Fixture-Authorization") == "synthetic-token"
                        && body?.keys.sorted() == ["prompt", "tier"]
                        && body?["tier"] == "balanced"
                        && body?["prompt"] == Self.expectedPrompt
                )
                return (data, Self.httpResponse())
            }
        )
        let client = Self.client(proxy: dependencies)
        let intent = try await client.interpret(Self.query, client.resolveProvider(.auto))
        #expect(intent == response.expectedIntent)
        #expect(authorizationCalls.value == 1)
        #expect(transportCalls.value == 1)
        let contractMatched = requestContractMatched.value
        #expect(contractMatched)
    }

    @Test
    func requestPreparationAndTransportFailures() async {
        let authorizationCalls = LockIsolated(0)
        let transportCalls = LockIsolated(0)
        let invalid = ProxyProvider.Dependencies(
            endpoint: "https://[",
            authorize: { _ in authorizationCalls.withValue { $0 += 1 } },
            now: { Self.now },
            calendar: Self.calendar,
            transport: { _ in
                transportCalls.withValue { $0 += 1 }
                return Self.completedProxy()
            }
        )
        await Self.expectFailure(.requestPreparation) {
            try await ProxyProvider.interpret(Self.query, dependencies: invalid)
        }
        #expect(authorizationCalls.value == 0)
        #expect(transportCalls.value == 0)

        let transport = Self.proxyDependencies { _ in throw SelfHostileError() }
        await Self.expectFailure(.transport) {
            try await ProxyProvider.interpret(Self.query, dependencies: transport)
        }
    }

    @Test(arguments: FailedResponse.allCases)
    func responseShapeAndHostileFailuresArePayloadFree(response: FailedResponse) async {
        let dependencies = Self.proxyDependencies { _ in response.response() }
        let client = Self.client(proxy: dependencies)
        let provider = client.resolveProvider(.proxy)
        await Self.expectFailure(response.expectedFailure) {
            try await client.interpret(Self.query, provider)
        }
    }

    @Test
    func onDeviceResultsAndUnavailable() async throws {
        #expect(AIDateHelper.provider(for: .auto, onDeviceSupported: false) == .proxy)
        #expect(AIDateHelper.provider(for: .auto, onDeviceSupported: true) == .proxy)
        #expect(AIDateHelper.provider(for: .proxy, onDeviceSupported: false) == .proxy)
        #expect(AIDateHelper.provider(for: .onDevice, onDeviceSupported: true) == .foundationModels)
        #expect(AIDateHelper.provider(for: .onDevice, onDeviceSupported: false) == .none)

        let proxyCalls = LockIsolated(0)
        let generatorCalls = LockIsolated(0)
        let promptMatched = LockIsolated(false)
        let dependencies = AIDateHelper.Dependencies(
            interpretProxy: { _ in
                proxyCalls.withValue { $0 += 1 }
                return .navigate(CivilDate(year: 2026, month: 12, day: 25)!)
            },
            now: { Self.now },
            calendar: Self.calendar,
            generateOnDevice: { instructions, prompt in
                generatorCalls.withValue { $0 += 1 }
                promptMatched.setValue(instructions + "\n" + prompt == Self.expectedPrompt)
                return AIIntentWire(intent: "navigate", date: "2026-03-15")
            }
        )
        let intent = try await AIDateHelper.interpret(
            Self.query, provider: .foundationModels, dependencies: dependencies
        )
        #expect(intent == .navigate(CivilDate(year: 2026, month: 3, day: 15)!))
        let actualPromptMatched = promptMatched.value
        #expect(actualPromptMatched)
        #expect(proxyCalls.value == 0)
        #expect(generatorCalls.value == 1)

        var noDate = dependencies
        noDate.generateOnDevice = { _, _ in AIIntentWire(intent: "teleport", date: "2026-03-15") }
        let noDateResult = try await AIDateHelper.interpret(
            Self.query, provider: .foundationModels, dependencies: noDate
        )
        #expect(noDateResult == nil)

        var failed = dependencies
        failed.generateOnDevice = { _, _ in throw SelfHostileError() }
        let failedDependencies = failed
        await Self.expectFailure(.onDeviceRequest) {
            try await AIDateHelper.interpret(
                Self.query, provider: .foundationModels, dependencies: failedDependencies
            )
        }
        let beforeProxy = proxyCalls.value
        let beforeGenerator = generatorCalls.value
        await Self.expectFailure(.unavailable) {
            try await AIDateHelper.interpret(
                Self.query, provider: .none, dependencies: dependencies
            )
        }
        #expect(proxyCalls.value == beforeProxy)
        #expect(generatorCalls.value == beforeGenerator)
    }

    @Test
    func cancellationWinsOverLateOutcome() async {
        for error in [CancellationError() as any Error, URLError(.cancelled)] {
            let dependencies = Self.proxyDependencies { _ in throw error }
            await #expect(throws: CancellationError.self) {
                try await ProxyProvider.interpret(Self.query, dependencies: dependencies)
            }
        }
        let canceledGenerator = AIDateHelper.Dependencies(
            interpretProxy: { _ in nil }, now: { Self.now },
            generateOnDevice: { _, _ in throw CancellationError() }
        )
        await #expect(throws: CancellationError.self) {
            try await AIDateHelper.interpret(
                Self.query, provider: .foundationModels, dependencies: canceledGenerator
            )
        }

        let start = AIDateClientGate()
        let calls = LockIsolated(0)
        let notStarted = Self.proxyDependencies { _ in
            calls.withValue { $0 += 1 }
            return Self.completedProxy()
        }
        let canceledBeforeWork = Task {
            await start.wait()
            return try await ProxyProvider.interpret(Self.query, dependencies: notStarted)
        }
        canceledBeforeWork.cancel()
        await start.open()
        await #expect(throws: CancellationError.self) { try await canceledBeforeWork.value }
        #expect(calls.value == 0)

        for provider in [AIDateHelper.Provider.proxy, .foundationModels] {
            for failsAfterCancellation in [false, true] {
                let entered = AIDateClientGate()
                let finish = AIDateClientGate()
                let proxy = Self.proxyDependencies { _ in
                    await entered.open()
                    await finish.wait()
                    if failsAfterCancellation { throw SelfHostileError() }
                    return Self.completedProxy()
                }
                let dependencies = AIDateHelper.Dependencies(
                    interpretProxy: { query in
                        try await ProxyProvider.interpret(query, dependencies: proxy)
                    },
                    now: { Self.now },
                    generateOnDevice: { _, _ in
                        await entered.open()
                        await finish.wait()
                        if failsAfterCancellation { throw SelfHostileError() }
                        return AIIntentWire(intent: "navigate", date: "2026-03-15")
                    }
                )
                let worker = Task {
                    try await AIDateHelper.interpret(
                        Self.query, provider: provider, dependencies: dependencies
                    )
                }
                await entered.wait()
                worker.cancel()
                await finish.open()
                await #expect(throws: CancellationError.self) { try await worker.value }
            }
        }
    }

    private static let endpoint = URL(string: "https://fixture.invalid/refine")!
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)
    private static let query = "synthetic next Friday"
    /// 2023-11-14T22:13:20Z is already Nov 15 in Kiritimati (UTC+14): the prompt must say the local day.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Pacific/Kiritimati")!
        return calendar
    }()
    private static let expectedPrompt = AIIntentPrompt.full(
        query: query, today: CivilDate(year: 2023, month: 11, day: 15)!,
        timeZone: TimeZone(identifier: "Pacific/Kiritimati")!
    )

    private static func httpResponse(status: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(url: endpoint, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    private static func completedProxy() -> (Data, URLResponse) {
        (Data("{\"text\":\"2026-03-15\"}".utf8), httpResponse())
    }

    private static func proxyDependencies(
        transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) -> ProxyProvider.Dependencies {
        ProxyProvider.Dependencies(
            endpoint: endpoint.absoluteString, authorize: { _ in },
            now: { Self.now }, calendar: calendar, transport: transport
        )
    }

    private static func client(proxy: ProxyProvider.Dependencies) -> AIDateQueryClient {
        let dependencies = AIDateHelper.Dependencies(
            interpretProxy: { query in
                try await ProxyProvider.interpret(query, dependencies: proxy)
            },
            now: { Self.now },
            generateOnDevice: { _, _ in
                Issue.record("Synthetic proxy routing must not invoke on-device generation.")
                return AIIntentWire(intent: "clarify")
            }
        )
        return AIDateQueryClient(
            resolveProvider: { AIDateHelper.provider(for: $0, onDeviceSupported: false) },
            interpret: {
                try await AIDateHelper.interpret(
                    $0, provider: $1, dependencies: dependencies
                )
            }
        )
    }

    private static func expectFailure(
        _ expected: AIDateFailure,
        operation: () async throws -> AIIntent?
    ) async {
        do {
            _ = try await operation()
            Issue.record("Expected a fixed AI failure category, received a completed outcome.")
        } catch {
            let exactCategoryMatched = (error as? AIDateFailure) == expected
            let payloadFree = !String(reflecting: error).contains(SelfHostileError.marker)
                && !error.localizedDescription.contains(SelfHostileError.marker)
            #expect(exactCategoryMatched)
            #expect(payloadFree)
        }
    }
}

private struct SelfHostileError: LocalizedError, Sendable {
    static let marker = "SYNTHETIC_PRIVATE_QUERY_RESPONSE_AUTH"
    var errorDescription: String? { Self.marker }
}

/// Buffered acknowledgements ignore task cancellation so each real worker can
/// finish after its gate is opened; tests await the worker, never a proxy observer.
private actor AIDateClientGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let waiting = waiters
        waiters.removeAll()
        for waiter in waiting { waiter.resume() }
    }
}
