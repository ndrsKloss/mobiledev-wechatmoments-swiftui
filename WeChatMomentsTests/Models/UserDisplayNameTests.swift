//
//  UserDisplayNameTests.swift
//  WeChatMomentsTests
//
//  The name fallback behind FR-TWEET-001 (the tweet's sender) and FR-TWEET-007 (a comment's
//  sender). Every field of `User` is optional (FR-API-002), so the last rung has to exist.
//

@testable import WeChatMoments
import XCTest

final class UserDisplayNameTests: XCTestCase {

    func test_the_nick_wins_when_present() {
        let user = User(username: "cyao", nick: "Cheng Yao", avatar: nil, profile: nil)

        XCTAssertEqual(user.displayName, "Cheng Yao")
    }

    func test_the_username_is_the_fallback() {
        let user = User(username: "cyao", nick: nil, avatar: nil, profile: nil)

        XCTAssertEqual(user.displayName, "cyao")
    }

    /// An empty nick is as absent as a missing one — the fixture's senders are well formed,
    /// but `""` would otherwise render a nameless comment row.
    func test_an_empty_nick_falls_through_to_the_username() {
        let user = User(username: "cyao", nick: "", avatar: nil, profile: nil)

        XCTAssertEqual(user.displayName, "cyao")
    }

    func test_a_user_with_no_name_at_all_is_unknown() {
        let user = User(username: nil, nick: nil, avatar: nil, profile: nil)

        XCTAssertEqual(user.displayName, "Unknown")
    }

    /// `Comment.sender` is itself optional (fn-spec §3.2), so the call site needs an
    /// answer for `nil` without an `if let` at every use.
    func test_an_absent_user_is_unknown() {
        let user: User? = nil

        XCTAssertEqual(user.displayName, "Unknown")
    }
}
