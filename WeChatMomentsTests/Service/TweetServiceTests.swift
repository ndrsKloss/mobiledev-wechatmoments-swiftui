//
//  TweetServiceTests.swift
//  WeChatMomentsTests
//
//  Offline, against MockBaseService (NFR-TEST-001/002). `test_wrong_url` previously took the
//  full ten-second timeout on every run: its `.failure` branch never fulfilled its expectation,
//  so the failure it was written to prove was indistinguishable from a hang.
//

@testable import WeChatMoments
import Combine
import XCTest

final class TweetServiceTests: XCTestCase {

    private func fixture() throws -> Data {
        let url = try XCTUnwrap(
            Bundle(for: TweetServiceTests.self).url(forResource: "Tweets", withExtension: "json"),
            "Tweets.json is not in the test bundle."
        )
        return try Data(contentsOf: url)
    }

    /// NFR-TEST-001 — the seam exists at all. Before the default-argument initialiser,
    /// `TweetService` hard-coded `HttpService()` and this test could not be written.
    func test_the_feed_endpoint_is_requested() throws {
        let http = MockBaseService(result: .success(try fixture()))
        let service = TweetService(httpService: http)

        _ = try awaitValue(service.getTweets(TestDataConfig.USER))

        XCTAssertEqual(http.callCount, 1)
        XCTAssertEqual(http.requestedUrls.first, UrlConstant.tweetsUrl(name: TestDataConfig.USER))
    }

    /// NFR-DATA-001 / FR-API-004 — the same 22-in / 17-out arithmetic TweetDecodingTests
    /// asserts on the model, now proven through the service that performs it.
    func test_a_well_formed_feed_decodes_leniently() throws {
        let service = TweetService(httpService: MockBaseService(result: .success(try fixture())))

        let tweets = try awaitValue(service.getTweets(TestDataConfig.USER))

        XCTAssertEqual(tweets.count, 17)
    }

    /// FR-API-005 — the replacement for the old `test_wrong_url`. A 404 is a failure, and the
    /// decoder is never reached.
    func test_a_404_fails_without_reaching_the_decoder() throws {
        let service = TweetService(httpService: MockBaseService(result: .failure(.httpStatus(404))))

        let error = try awaitFailure(service.getTweets("jsmitn2"))

        XCTAssertHttpStatus(error, 404)
    }

    /// A 2xx body the model cannot read is a different failure from a bad status, and the
    /// typed error keeps them apart (FAD-DATA-b).
    func test_an_unreadable_body_fails_as_decoding() throws {
        let service = TweetService(httpService: MockBaseService(json: #"{"not":"an array"}"#))

        let error = try awaitFailure(service.getTweets(TestDataConfig.USER))

        XCTAssertIsDecodingFailure(error)
    }

    /// Mountebank being down reaches the caller as `.transport`, not as an empty feed.
    func test_a_transport_failure_propagates() throws {
        let service = TweetService(
            httpService: MockBaseService(result: .failure(.transport(URLError(.cannotConnectToHost))))
        )

        let error = try awaitFailure(service.getTweets(TestDataConfig.USER))

        XCTAssertIsTransportFailure(error)
    }

    /// An empty array is a legitimate feed, not an error.
    func test_an_empty_feed_is_a_success() throws {
        let service = TweetService(httpService: MockBaseService(json: "[]"))

        let tweets = try awaitValue(service.getTweets(TestDataConfig.USER))

        XCTAssertTrue(tweets.isEmpty)
    }
}
