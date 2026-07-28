//
//  UserServiceTests.swift
//  WeChatMomentsTests
//
//  Offline, against MockBaseService (NFR-TEST-001/002).
//
//  Both of the tests these replace were wrong. `test_right_url` asserted the returned username
//  was `jsmith` while the mock serves `hengzeng`, and failed. `test_wrong_url` passed for the
//  wrong reason: the catch-all stub's 404 body decoded into an all-`nil` `User` through the
//  *success* path, so the assertions it made were satisfied by the very defect this commit
//  fixes (FR-API-005).
//

@testable import WeChatMoments
import Combine
import XCTest

final class UserServiceTests: XCTestCase {

    private let profileJson = """
    {
      "profile-image": "https://example.invalid/profile.jpeg",
      "avatar": "https://example.invalid/avatar.png",
      "nick": "Huan Huan",
      "username": "hengzeng"
    }
    """

    func test_the_profile_endpoint_is_requested() throws {
        let http = MockBaseService(json: profileJson)
        let service = UserService(httpService: http)

        _ = try awaitValue(service.getUserProfile(TestDataConfig.USER))

        XCTAssertEqual(http.callCount, 1)
        XCTAssertEqual(http.requestedUrls.first, UrlConstant.userProfileUrl(name: TestDataConfig.USER))
    }

    /// FR-API-001 — the hyphenated key reaches `User.profile` through the service, not just
    /// through a bare `JSONDecoder`.
    func test_a_profile_decodes_including_the_hyphenated_key() throws {
        let service = UserService(httpService: MockBaseService(json: profileJson))

        let user = try awaitValue(service.getUserProfile(TestDataConfig.USER))

        XCTAssertEqual(user.username, "hengzeng")
        XCTAssertEqual(user.nick, "Huan Huan")
        XCTAssertEqual(user.profile, "https://example.invalid/profile.jpeg")
        XCTAssertEqual(user.avatar, "https://example.invalid/avatar.png")
    }

    /// FR-API-005 / NFR-DATA-003 — this is the test that used to pass for the wrong reason.
    /// A 404 must now be a failure; an all-`nil` `User` is no longer an acceptable answer,
    /// because it is indistinguishable from a genuinely empty profile.
    func test_a_404_fails_rather_than_decoding_an_empty_user() throws {
        let service = UserService(httpService: MockBaseService(result: .failure(.httpStatus(404))))

        let error = try awaitFailure(service.getUserProfile("jsmitn2"))

        XCTAssertHttpStatus(error, 404)
    }

    /// FR-API-002 — every field is optional, so an empty object is a valid profile and must
    /// not be confused with the 404 case above.
    func test_an_empty_object_is_a_valid_profile() throws {
        let service = UserService(httpService: MockBaseService(json: "{}"))

        let user = try awaitValue(service.getUserProfile(TestDataConfig.USER))

        XCTAssertNil(user.username)
        XCTAssertNil(user.nick)
        XCTAssertNil(user.avatar)
        XCTAssertNil(user.profile)
    }

    func test_an_unreadable_body_fails_as_decoding() throws {
        let service = UserService(httpService: MockBaseService(json: "not json at all"))

        let error = try awaitFailure(service.getUserProfile(TestDataConfig.USER))

        XCTAssertIsDecodingFailure(error)
    }
}
