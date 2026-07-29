//
//  PublisherTestHelpers.swift
//  WeChatMomentsTests
//
//  Collects a publisher's outcome without the expectation-per-branch shape that let
//  `TweetServiceTests.test_wrong_url` hang for ten seconds on every run: its `.failure` branch
//  never fulfilled its expectation, so the failure it was written to prove looked like a
//  timeout. Here every terminal event settles the same expectation.
//

@testable import WeChatMoments
import Combine
import XCTest

extension XCTestCase {

    /// Runs `publisher` to completion and returns its outcome, failing the test on timeout.
    func awaitOutcome<P: Publisher>(
        _ publisher: P,
        timeout: TimeInterval = 1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Result<P.Output, P.Failure>? {
        let settled = expectation(description: "publisher settled")
        var outcome: Result<P.Output, P.Failure>?

        let cancellable = publisher.sink { completion in
            if case let .failure(error) = completion {
                outcome = .failure(error)
            }
            settled.fulfill()
        } receiveValue: { value in
            outcome = .success(value)
        }

        wait(for: [settled], timeout: timeout)
        cancellable.cancel()

        if outcome == nil {
            XCTFail("The publisher completed without a value and without an error.", file: file, line: line)
        }
        return outcome
    }

    /// Asserts a publisher succeeds, returning its value.
    func awaitValue<P: Publisher>(
        _ publisher: P,
        timeout: TimeInterval = 1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> P.Output {
        switch awaitOutcome(publisher, timeout: timeout, file: file, line: line) {
        case let .success(value):
            return value
        case let .failure(error):
            XCTFail("Expected a value, got \(error).", file: file, line: line)
            throw error
        case nil:
            throw NetworkError.invalidResponse
        }
    }

    /// Waits for a `@Published` property to reach a value satisfying `predicate`.
    ///
    /// `MockBaseService` answers synchronously, but the view model's `.receive(on: RunLoop.main)`
    /// (`NFR-PERF-004`) defers delivery by a runloop turn, so an assertion made straight after
    /// `loadInitialData()` would read the pre-delivery state. This waits for the turn without
    /// reaching for a sleep.
    func awaitPublished<P: Publisher>(
        _ publisher: P,
        timeout: TimeInterval = 1,
        file: StaticString = #filePath,
        line: UInt = #line,
        until predicate: @escaping (P.Output) -> Bool
    ) where P.Failure == Never {
        let settled = expectation(description: "published value satisfied the predicate")
        settled.assertForOverFulfill = false

        let cancellable = publisher.sink { value in
            if predicate(value) { settled.fulfill() }
        }

        wait(for: [settled], timeout: timeout)
        cancellable.cancel()
    }

    /// Asserts a publisher fails, returning its error.
    func awaitFailure<P: Publisher>(
        _ publisher: P,
        timeout: TimeInterval = 1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> P.Failure {
        switch awaitOutcome(publisher, timeout: timeout, file: file, line: line) {
        case let .failure(error):
            return error
        case let .success(value):
            XCTFail("Expected a failure, got \(value).", file: file, line: line)
            throw NetworkError.invalidResponse
        case nil:
            throw NetworkError.invalidResponse
        }
    }
}

/// `NetworkError` deliberately does not conform to `Equatable` — `.transport` and `.decoding`
/// carry payloads that are not (`FAD-DATA-b`). Tests match on the case instead.
func XCTAssertHttpStatus(
    _ error: NetworkError,
    _ expected: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard case let .httpStatus(code) = error else {
        return XCTFail("Expected .httpStatus(\(expected)), got \(error).", file: file, line: line)
    }
    XCTAssertEqual(code, expected, file: file, line: line)
}

func XCTAssertIsDecodingFailure(
    _ error: NetworkError,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard case .decoding = error else {
        return XCTFail("Expected .decoding, got \(error).", file: file, line: line)
    }
}

func XCTAssertIsTransportFailure(
    _ error: NetworkError,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard case .transport = error else {
        return XCTFail("Expected .transport, got \(error).", file: file, line: line)
    }
}
