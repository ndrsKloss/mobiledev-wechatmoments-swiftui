//
//  TweetDecodingTests.swift
//  WeChatMomentsTests
//
//  Offline decoding tests. These read the committed fixture and need no network and no
//  running mountebank (NFR-TEST-002, NFR-TEST-003).
//

@testable import WeChatMoments
import XCTest

final class TweetDecodingTests: XCTestCase {

    private var fixture: Data!

    override func setUpWithError() throws {
        let url = try XCTUnwrap(
            Bundle(for: TweetDecodingTests.self).url(forResource: "Tweets", withExtension: "json"),
            "Tweets.json is not in the test bundle."
        )
        fixture = try Data(contentsOf: url)
    }

    /// Guards the fixture against drift: the arithmetic below is only meaningful if the
    /// served feed is still the 22-element array described in fn-spec §3.3.
    func test_fixture_has_22_elements() throws {
        let raw = try JSONSerialization.jsonObject(with: fixture) as? [Any]
        XCTAssertEqual(raw?.count, 22)
    }

    /// NFR-DATA-001 / FR-API-004 — the five malformed elements are dropped individually
    /// and the remaining seventeen survive intact.
    func test_malformed_elements_are_dropped_without_failing_the_feed() throws {
        let tweets = try decodeLeniently()

        XCTAssertEqual(tweets.count, 17, "22 elements in, 5 malformed, 17 out.")
    }

    /// The atomic-decode trap in fn-spec §3.3: decoding the array as `[Tweet]` must fail
    /// outright. This is the reason the lenient path exists — if this test ever starts
    /// passing, the tolerance above has become decorative.
    func test_strict_decoding_of_the_whole_array_fails() {
        XCTAssertThrowsError(try JSONDecoder().decode([Tweet].self, from: fixture))
    }

    /// FR-API-003 — sender, content, images and comments all reach the model.
    func test_decodes_sender_content_images_and_comments() throws {
        let tweets = try decodeLeniently()
        let first = try XCTUnwrap(tweets.first)

        XCTAssertEqual(first.sender.nick, "Cheng Yao")
        XCTAssertEqual(first.sender.username, "cyao")
        XCTAssertEqual(first.content, "First post!")
        XCTAssertEqual(first.images?.count, 3)
        XCTAssertEqual(first.comments?.count, 2)
        XCTAssertEqual(first.comments?.first?.sender?.nick, "Lei Huang")
    }

    /// FR-TWEET-004 — the feed carries one element at the maximum of 9 images.
    func test_the_nine_image_tweet_decodes_all_nine() throws {
        let tweets = try decodeLeniently()

        XCTAssertEqual(tweets.filter { $0.images?.count == 9 }.count, 1)
        XCTAssertNil(tweets.first { ($0.images?.count ?? 0) > 9 })
    }

    /// An *empty* comment array is distinct from an absent one — two elements carry
    /// `"comments": []`, and the rendering rule in FR-TWEET-008 depends on telling them apart.
    func test_empty_comment_arrays_decode_as_empty_not_nil() throws {
        let tweets = try decodeLeniently()

        XCTAssertEqual(tweets.filter { $0.comments?.isEmpty == true }.count, 2)
    }

    /// Two elements carry a sender and nothing else. They decode successfully here;
    /// dropping them from display is FR-DATA-001's job, at the view-model boundary.
    func test_sender_only_elements_still_decode() throws {
        let tweets = try decodeLeniently()
        let empty = tweets.filter { $0.content == nil && $0.images == nil }

        XCTAssertEqual(empty.count, 2)
    }

    /// NFR-DATA-007 / FAD-DATA-d — identity is assigned client-side, so tweets with
    /// identical content do not collide.
    func test_identity_is_unique_across_identical_content() throws {
        let tweets = try decodeLeniently()
        let sender = User(username: "a", nick: nil, avatar: nil, profile: nil)
        let twins = [
            Tweet(sender: sender, content: "same", images: nil, comments: nil),
            Tweet(sender: sender, content: "same", images: nil, comments: nil)
        ]

        XCTAssertNotEqual(twins[0].id, twins[1].id)
        XCTAssertEqual(Set(tweets.map(\.id)).count, tweets.count)
    }

    /// FR-API-001 — the profile payload key is hyphenated and must be mapped.
    func test_user_maps_the_hyphenated_profile_image_key() throws {
        let json = Data("""
        {
          "profile-image": "https://example.invalid/profile.jpeg",
          "avatar": "https://example.invalid/avatar.png",
          "nick": "Huan Huan",
          "username": "hengzeng"
        }
        """.utf8)

        let user = try JSONDecoder().decode(User.self, from: json)

        XCTAssertEqual(user.profile, "https://example.invalid/profile.jpeg")
        XCTAssertEqual(user.avatar, "https://example.invalid/avatar.png")
        XCTAssertEqual(user.nick, "Huan Huan")
        XCTAssertEqual(user.username, "hengzeng")
    }

    /// FR-API-002 — every user field is optional; an empty object is not an error.
    func test_user_fields_are_all_optional() throws {
        let user = try JSONDecoder().decode(User.self, from: Data("{}".utf8))

        XCTAssertNil(user.username)
        XCTAssertNil(user.nick)
        XCTAssertNil(user.avatar)
        XCTAssertNil(user.profile)
    }

    // MARK: - Helpers

    /// Mirrors what `TweetService` does with the response body.
    private func decodeLeniently() throws -> [Tweet] {
        try JSONDecoder()
            .decode([FailableDecodable<Tweet>].self, from: fixture)
            .compactMap(\.value)
    }
}
