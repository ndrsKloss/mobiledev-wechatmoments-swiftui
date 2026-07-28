//
//  HttpServiceIntegrationTests.swift
//  WeChatMomentsTests
//
//  The only tests in this project that need a running mountebank (FAD-TEST-a). They are
//  identifiable by folder and by name, per NFR-TEST-004, and skip rather than fail when the
//  mock is not running so the offline suite stays green (NFR-TEST-002):
//
//      mb --configfile imposters.ejs        # to actually exercise them
//      -only-testing:WeChatMomentsTests/HttpServiceIntegrationTests
//
//  Everything else about the networking layer is proven offline; what only a real server can
//  prove is that the endpoints and the served payloads are still what the app expects.
//

@testable import WeChatMoments
import Combine
import XCTest

final class HttpServiceIntegrationTests: XCTestCase {

    private var service: HttpService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(Mountebank.isReachable, "mountebank is not running on \(TestDataConfig.URL_HOST).")
        service = HttpService()
    }

    /// The feed endpoint answers, and it answers with the 22-element array the fixture and
    /// fn-spec §3.3 both describe. This is the check that catches `imposters.ejs` drifting
    /// away from `WeChatMomentsTests/Resources/Tweets.json`.
    func test_the_live_feed_matches_the_committed_fixture_shape() throws {
        let url = UrlConstant.tweetsUrl(name: TestDataConfig.USER)

        let data = try awaitValue(service.get(url: url), timeout: 10)
        let elements = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [Any])

        XCTAssertEqual(elements.count, 22)
    }

    func test_the_live_profile_endpoint_answers() throws {
        let url = UrlConstant.userProfileUrl(name: TestDataConfig.USER)

        let data = try awaitValue(service.get(url: url), timeout: 10)
        let user = try JSONDecoder().decode(User.self, from: data)

        XCTAssertNotNil(user.username)
    }

    /// FR-API-005 against the real catch-all stub — the one place the 404 is genuine rather
    /// than scripted. This is what the old `test_wrong_url` tests were reaching for.
    func test_the_live_catch_all_stub_is_surfaced_as_a_404() throws {
        let url = UrlConstant.userProfileUrl(name: "jsmitn2")

        let error = try awaitFailure(service.get(url: url), timeout: 10)

        XCTAssertHttpStatus(error, 404)
    }
}
