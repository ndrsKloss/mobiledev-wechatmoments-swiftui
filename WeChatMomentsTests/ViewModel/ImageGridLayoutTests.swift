//
//  ImageGridLayoutTests.swift
//  WeChatMomentsTests
//
//  fn-spec §5 as a pure function over an image count — no view, no view model, no network
//  (NFR-TEST-002, NFR-TEST-006).
//
//  The table matters more than usual here. Two of its rows are tagged `[A]` in the spec because
//  the reference screenshots contain neither a 1- nor a 4-image tweet, and the served feed only
//  ever carries 0, 1, 3, 4 or 9 images — so counts 2 and 5…8 have no other way of being pinned.
//

@testable import WeChatMoments
import XCTest

final class ImageGridLayoutTests: XCTestCase {

    private var fixture: Data!

    override func setUpWithError() throws {
        let url = try XCTUnwrap(
            Bundle(for: ImageGridLayoutTests.self).url(forResource: "Tweets", withExtension: "json"),
            "Tweets.json is not in the test bundle."
        )
        fixture = try Data(contentsOf: url)
    }

    // MARK: - fn-spec §5, row by row

    /// FR-TWEET-004: no images, no grid. Not "an empty grid" — nothing at all.
    func test_no_images_yields_no_grid() {
        XCTAssertNil(ImageGridLayout.plan(forImageCount: 0))
    }

    /// §5 row 1 `[A]`: a single image is larger than a grid cell — two of the three columns.
    func test_one_image_spans_two_columns() {
        XCTAssertEqual(
            ImageGridLayout.plan(forImageCount: 1),
            ImageGridLayout.Plan(imagesPerRow: 1, columnSpan: 2)
        )
    }

    /// §5 row 2: one row of three columns, left-aligned. Two images do not stretch to fill.
    func test_two_and_three_images_use_one_three_column_row() {
        for count in 2...3 {
            XCTAssertEqual(
                ImageGridLayout.plan(forImageCount: count),
                ImageGridLayout.Plan(imagesPerRow: 3, columnSpan: 1),
                "count \(count)"
            )
        }
    }

    /// §5 row 3 `[A]`: the classic WeChat 2×2. Cells stay one third of the width — the block is
    /// two columns wide, not half the row each.
    func test_four_images_use_a_two_by_two_block() {
        XCTAssertEqual(
            ImageGridLayout.plan(forImageCount: 4),
            ImageGridLayout.Plan(imagesPerRow: 2, columnSpan: 1)
        )
    }

    /// §5 rows 4 and 5: everything from 5 to 9 is the plain three-column grid.
    func test_five_to_nine_images_use_three_columns() {
        for count in 5...9 {
            XCTAssertEqual(
                ImageGridLayout.plan(forImageCount: count),
                ImageGridLayout.Plan(imagesPerRow: 3, columnSpan: 1),
                "count \(count)"
            )
        }
    }

    /// The contract says 1…9 (FR-TWEET-004). The function stays total anyway: a payload that
    /// breaks the contract must not trap, and 10 images in a 3-column grid is the sane answer.
    func test_counts_beyond_the_contract_do_not_trap() {
        XCTAssertEqual(
            ImageGridLayout.plan(forImageCount: 10),
            ImageGridLayout.Plan(imagesPerRow: 3, columnSpan: 1)
        )
        XCTAssertNil(ImageGridLayout.plan(forImageCount: -1))
    }

    // MARK: - Chunking into rows

    func test_four_images_chunk_into_two_rows_of_two() {
        XCTAssertEqual(ImageGridLayout.rows([1, 2, 3, 4], perRow: 2), [[1, 2], [3, 4]])
    }

    func test_nine_images_chunk_into_three_full_rows() {
        XCTAssertEqual(
            ImageGridLayout.rows(Array(1...9), perRow: 3),
            [[1, 2, 3], [4, 5, 6], [7, 8, 9]]
        )
    }

    /// The partial row is the last one and it is not padded — FR-TWEET-004 wants exactly as many
    /// cells as there are images. The padding that keeps the columns aligned is a view concern.
    func test_a_partial_last_row_keeps_only_the_images_it_has() {
        XCTAssertEqual(ImageGridLayout.rows(Array(1...5), perRow: 3), [[1, 2, 3], [4, 5]])
    }

    func test_order_is_preserved_left_to_right_then_down() {
        XCTAssertEqual(ImageGridLayout.rows(Array(1...7), perRow: 3).flatMap { $0 }, Array(1...7))
    }

    func test_no_images_chunk_into_no_rows() {
        XCTAssertEqual(ImageGridLayout.rows([Int](), perRow: 3), [])
    }

    // MARK: - Against the served feed

    /// The counts fn-spec §3.3 implies, made explicit: the fixture exercises 0, 1, 3, 4 and 9 and
    /// nothing else — so §5's rows for 2 and 5…8 are never drawn by the served feed and are pinned
    /// only by the hand-written cases above.
    func test_the_fixture_exercises_only_these_image_counts() throws {
        let counts = Set(try displayableTweets().map { $0.images?.count ?? 0 })

        XCTAssertEqual(counts, [0, 1, 3, 4, 9])
    }

    /// Every displayable tweet has a grid to draw — the filter (FR-DATA-001/002) has already
    /// dropped the ones with neither content nor images, so a nil plan here means text only.
    func test_every_displayable_tweet_with_images_has_a_plan() throws {
        for tweet in try displayableTweets() {
            let count = tweet.images?.count ?? 0
            guard count > 0 else { continue }

            XCTAssertNotNil(ImageGridLayout.plan(forImageCount: count), "count \(count)")
        }
    }

    /// The dominant case: six of the nine image tweets in the served feed carry exactly one
    /// image, which is why the §5 row that is tagged `[A]` is also the one most on screen.
    func test_single_image_tweets_are_the_most_common_image_tweet() throws {
        let withImages = try displayableTweets().compactMap { $0.images?.count }.filter { $0 > 0 }

        XCTAssertEqual(withImages.count, 9)
        XCTAssertEqual(withImages.filter { $0 == 1 }.count, 6)
    }

    // MARK: - Helpers

    /// Mirrors what `TweetService` and `MomentsViewModel` do with the response body.
    private func displayableTweets() throws -> [Tweet] {
        TweetFilter.displayable(
            try JSONDecoder()
                .decode([FailableDecodable<Tweet>].self, from: fixture)
                .compactMap(\.value)
        )
    }
}
