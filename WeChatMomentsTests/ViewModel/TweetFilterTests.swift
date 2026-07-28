//
//  TweetFilterTests.swift
//  WeChatMomentsTests
//
//  FR-DATA-001/002 as a pure function over `[Tweet]` — no view, no view model, no network
//  (NFR-TEST-002, NFR-TEST-006).
//

@testable import WeChatMoments
import XCTest

final class TweetFilterTests: XCTestCase {

    private var fixture: Data!

    override func setUpWithError() throws {
        let url = try XCTUnwrap(
            Bundle(for: TweetFilterTests.self).url(forResource: "Tweets", withExtension: "json"),
            "Tweets.json is not in the test bundle."
        )
        fixture = try Data(contentsOf: url)
    }

    // MARK: - Against the served feed

    /// The arithmetic fn-spec §3.3 states: 22 elements in, 5 malformed, 17 decode,
    /// 2 of those are sender-only, 15 are displayable.
    func test_the_served_feed_yields_fifteen_displayable_tweets() throws {
        let displayable = TweetFilter.displayable(try decodeLeniently())

        XCTAssertEqual(displayable.count, 15, "17 decoded, 2 sender-only dropped.")
    }

    /// FR-DATA-002 — the regression this filter exists to prevent. The previous rule,
    /// `$0.content != nil`, discarded every one of these.
    func test_image_only_tweets_survive() throws {
        let displayable = TweetFilter.displayable(try decodeLeniently())
        let imageOnly = displayable.filter { $0.content == nil && ($0.images?.isEmpty == false) }

        XCTAssertEqual(imageOnly.count, 4)
    }

    /// FR-DATA-001 — a tweet with neither content nor images is not displayed.
    func test_sender_only_tweets_are_dropped() throws {
        let displayable = TweetFilter.displayable(try decodeLeniently())

        XCTAssertTrue(displayable.allSatisfy { $0.content != nil || $0.images != nil })
    }

    /// Filtering must not reorder the feed — pagination indices depend on it (FR-DATA-004).
    func test_order_is_preserved() throws {
        let decoded = try decodeLeniently()
        let displayable = TweetFilter.displayable(decoded)

        XCTAssertEqual(
            displayable.map(\.id),
            decoded.filter(TweetFilter.isDisplayable).map(\.id)
        )
        XCTAssertEqual(displayable.first?.content, "First post!")
    }

    // MARK: - The rule itself

    func test_a_tweet_with_content_and_no_images_is_displayable() {
        XCTAssertTrue(TweetFilter.isDisplayable(tweet(content: "hello", images: nil)))
    }

    func test_a_tweet_with_images_and_no_content_is_displayable() {
        XCTAssertTrue(TweetFilter.isDisplayable(tweet(content: nil, images: [image])))
    }

    func test_a_tweet_with_neither_is_not_displayable() {
        XCTAssertFalse(TweetFilter.isDisplayable(tweet(content: nil, images: nil)))
    }

    /// An empty array and an empty string are as absent as `nil` — a cell built from either
    /// would render blank. Not present in the fixture; asserted so the rule stays honest.
    func test_empty_content_and_empty_images_count_as_absent() {
        XCTAssertFalse(TweetFilter.isDisplayable(tweet(content: "", images: [])))
        XCTAssertFalse(TweetFilter.isDisplayable(tweet(content: "", images: nil)))
        XCTAssertFalse(TweetFilter.isDisplayable(tweet(content: nil, images: [])))
        XCTAssertTrue(TweetFilter.isDisplayable(tweet(content: "", images: [image])))
    }

    // MARK: - Helpers

    private let image = Img(url: "https://example.invalid/1.jpeg")

    private func tweet(content: String?, images: [Img]?) -> Tweet {
        Tweet(
            sender: User(username: "cyao", nick: "Cheng Yao", avatar: nil, profile: nil),
            content: content,
            images: images,
            comments: nil
        )
    }

    /// Mirrors what `TweetService` does with the response body.
    private func decodeLeniently() throws -> [Tweet] {
        try JSONDecoder()
            .decode([FailableDecodable<Tweet>].self, from: fixture)
            .compactMap(\.value)
    }
}
