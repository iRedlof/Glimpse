import ComposableArchitecture
import Foundation
import GlimpseCore
import Testing
@testable import Glimpse

struct AIDateQueryClientTests {
    enum CompletedResponse: String, CaseIterable, Sendable {
        case iso, embedded, whitespaceISO, noDate, empty, whitespaceOnly

        var text: String {
            switch self {
            case .iso: "2026-03-15"
            case .embedded: "The date is 2026-12-25 for Christmas"
            case .whitespaceISO: "  2026-01-01  \n"
            case .noDate: "not a date at all"
            case .empty: ""
            case .whitespaceOnly: " \n\t "
            }
        }

        var expectedComponents: DateComponents? {
            switch self {
            case .iso: DateComponents(year: 2026, month: 3, day: 15)
            case .embedded: DateComponents(year: 2026, month: 12, day: 25)
            case .whitespaceISO: DateComponents(year: 2026, month: 1, day: 1)
            case .noDate, .empty, .whitespaceOnly: nil
            }
        }
    }

    enum FailedResponse: String, CaseIterable, Sendable {
        case nonHTTP, badRequest, serverError, malformedJSON
        case arrayJSON, missingText, nullText, numericText

        var expectedFailure: AIDateFailure {
            switch self {
            case .nonHTTP: .nonHTTPResponse
            case .badRequest, .serverError: .nonSuccessResponse
            case .malformedJSON, .arrayJSON, .missingText, .nullText, .numericText:
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
    func proxyDateAndCompletedNoDate(response: CompletedResponse) async throws {
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
                        && body?["tier"] == "balanced"
                        && body?["prompt"] == Self.expectedPrompt
                )
                return (data, Self.httpResponse())
            }
        )
        let client = Self.client(proxy: dependencies)
        let date = try await client.parseDate(Self.query, client.resolveProvider(.auto))
        let components = date.map {
            Calendar.current.dateComponents([.year, .month, .day], from: $0)
        }
        #expect(components == response.expectedComponents)
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
            transport: { _ in
                transportCalls.withValue { $0 += 1 }
                return Self.completedProxy()
            }
        )
        await Self.expectFailure(.requestPreparation) {
            try await ProxyProvider.parseDate(Self.query, dependencies: invalid)
        }
        #expect(authorizationCalls.value == 0)
        #expect(transportCalls.value == 0)

        let transport = Self.proxyDependencies { _ in throw SelfHostileError() }
        await Self.expectFailure(.transport) {
            try await ProxyProvider.parseDate(Self.query, dependencies: transport)
        }
    }

    @Test(arguments: FailedResponse.allCases)
    func responseShapeAndHostileFailuresArePayloadFree(response: FailedResponse) async {
        let dependencies = Self.proxyDependencies { _ in response.response() }
        let client = Self.client(proxy: dependencies)
        let provider = client.resolveProvider(.proxy)
        await Self.expectFailure(response.expectedFailure) {
            try await client.parseDate(Self.query, provider)
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
            parseProxy: { _ in
                proxyCalls.withValue { $0 += 1 }
                return DateParser.extractDate(from: "2026-12-25")
            },
            now: { Self.now },
            generateOnDevice: { prompt in
                generatorCalls.withValue { $0 += 1 }
                promptMatched.setValue(prompt == Self.expectedPrompt)
                return "  2026-03-15  \n"
            }
        )
        let date = try await AIDateHelper.parseNaturalLanguageDate(
            Self.query, provider: .foundationModels, dependencies: dependencies
        )
        let components = date.map {
            Calendar.current.dateComponents([.year, .month, .day], from: $0)
        }
        #expect(components == DateComponents(year: 2026, month: 3, day: 15))
        let actualPromptMatched = promptMatched.value
        #expect(actualPromptMatched)
        #expect(proxyCalls.value == 0)
        #expect(generatorCalls.value == 1)

        var noDate = dependencies
        noDate.generateOnDevice = { _ in "no supported date" }
        let noDateResult = try await AIDateHelper.parseNaturalLanguageDate(
            Self.query, provider: .foundationModels, dependencies: noDate
        )
        #expect(noDateResult == nil)

        var failed = dependencies
        failed.generateOnDevice = { _ in throw SelfHostileError() }
        let failedDependencies = failed
        await Self.expectFailure(.onDeviceRequest) {
            try await AIDateHelper.parseNaturalLanguageDate(
                Self.query, provider: .foundationModels, dependencies: failedDependencies
            )
        }
        let beforeProxy = proxyCalls.value
        let beforeGenerator = generatorCalls.value
        await Self.expectFailure(.unavailable) {
            try await AIDateHelper.parseNaturalLanguageDate(
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
                try await ProxyProvider.parseDate(Self.query, dependencies: dependencies)
            }
        }
        let canceledGenerator = AIDateHelper.Dependencies(
            parseProxy: { _ in nil }, now: { Self.now },
            generateOnDevice: { _ in throw CancellationError() }
        )
        await #expect(throws: CancellationError.self) {
            try await AIDateHelper.parseNaturalLanguageDate(
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
            return try await ProxyProvider.parseDate(Self.query, dependencies: notStarted)
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
                    parseProxy: { query in
                        try await ProxyProvider.parseDate(query, dependencies: proxy)
                    },
                    now: { Self.now },
                    generateOnDevice: { _ in
                        await entered.open()
                        await finish.wait()
                        if failsAfterCancellation { throw SelfHostileError() }
                        return "2026-03-15"
                    }
                )
                let worker = Task {
                    try await AIDateHelper.parseNaturalLanguageDate(
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
    private static let expectedPrompt = "Respond with ONLY a date in yyyy-MM-dd format, nothing else. If the query is relative, today is 2023-11-14T22:13:20Z. Query: synthetic next Friday"

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
            now: { Self.now }, transport: transport
        )
    }

    private static func client(proxy: ProxyProvider.Dependencies) -> AIDateQueryClient {
        let dependencies = AIDateHelper.Dependencies(
            parseProxy: { query in
                try await ProxyProvider.parseDate(query, dependencies: proxy)
            },
            now: { Self.now },
            generateOnDevice: { _ in
                Issue.record("Synthetic proxy routing must not invoke on-device generation.")
                return ""
            }
        )
        return AIDateQueryClient(
            resolveProvider: { AIDateHelper.provider(for: $0, onDeviceSupported: false) },
            parseDate: {
                try await AIDateHelper.parseNaturalLanguageDate(
                    $0, provider: $1, dependencies: dependencies
                )
            }
        )
    }

    private static func expectFailure(
        _ expected: AIDateFailure,
        operation: () async throws -> Date?
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
