//
//  MomentsViewModelTests.swift
//  WeChatMomentsTests
//
//  The window, the loading flag and the error state, asserted with no view instantiated
//  (NFR-TEST-005) and no network (NFR-TEST-002). The seam these tests run through is the one
//  commit 06 opened: `MomentsViewModel` takes its services by injection, and they in turn take
//  the already-mockable `BaseService`.
//

@testable import WeChatMoments
import XCTest

final class MomentsViewModelTests: XCTestCase {

    private var feedFixture: Data!

    override func setUpWithError() throws {
        let url = try XCTUnwrap(
            Bundle(for: MomentsViewModelTests.self).url(forResource: "Tweets", withExtension: "json"),
            "Tweets.json is not in the test bundle."
        )
        feedFixture = try Data(contentsOf: url)   // NFR-TEST-003
    }

    // MARK: - The window

    /// FR-PAGE-001 with FR-FEED-001: five shown, fifteen held. The pair is the whole README
    /// bullet — "all tweets are fetched and stored in memory, but only 5 items are shown".
    func test_initial_load_shows_five_of_the_fifteen_it_holds() {
        let viewModel = makeViewModel()

        viewModel.loadInitialData()
        awaitPublished(viewModel.$feed) { !$0.isLoading }

        XCTAssertEqual(viewModel.allTweets.count, 15, "The full filtered feed stays in memory.")
        XCTAssertEqual(viewModel.displayedTweets.count, 5)
        XCTAssertEqual(viewModel.displayedCount, 5)
    }

    /// arch-spec §7.1: the window is a prefix of the stored feed, in order — not a second array
    /// and not a re-ordering.
    func test_the_window_is_the_first_five_in_order() {
        let viewModel = makeViewModel()

        viewModel.loadInitialData()
        awaitPublished(viewModel.$feed) { !$0.isLoading }

        XCTAssertEqual(viewModel.displayedTweets.map(\.id), viewModel.allTweets.prefix(5).map(\.id))
        XCTAssertEqual(viewModel.displayedTweets.first?.content, "First post!")
    }

    /// fn-spec §8 Q6: fewer displayable tweets than a page renders what exists — no padding, and
    /// no count that overruns the array. Not reachable with the served fixture, which is why it
    /// is pinned here.
    func test_a_feed_shorter_than_a_page_shows_what_exists() {
        let twoTweets = """
        [{"content": "one", "sender": {"nick": "A"}}, {"content": "two", "sender": {"nick": "B"}}]
        """
        let viewModel = makeViewModel(feed: .init(json: twoTweets))

        viewModel.loadInitialData()
        awaitPublished(viewModel.$feed) { !$0.isLoading }

        XCTAssertEqual(viewModel.displayedCount, 2)
        XCTAssertEqual(viewModel.displayedTweets.count, 2)
    }

    // MARK: - Appending (FR-PAGE-002/003)

    /// FR-PAGE-002: one page at a time, over the feed already in memory. The stored feed is
    /// untouched by the append — that is `FR-FEED-002`, the reason no request is involved.
    func test_appending_grows_the_window_by_one_page() {
        let viewModel = makeViewModel()

        viewModel.loadInitialData()
        awaitPublished(viewModel.$feed) { !$0.isLoading }
        viewModel.loadNextPage()

        XCTAssertEqual(viewModel.displayedCount, 10)
        XCTAssertEqual(viewModel.displayedTweets.count, 10)
        XCTAssertEqual(viewModel.allTweets.count, 15, "Appending must not re-fetch or re-filter.")
    }

    /// `nfr §4.5`'s acceptance sequence, minus the refresh leg that commit 08 owns: 5 → 10 → 15.
    /// The window stays a prefix in order at every step (`arch-spec §7.1`).
    func test_appending_twice_reaches_the_last_page() {
        let viewModel = makeViewModel()

        viewModel.loadInitialData()
        awaitPublished(viewModel.$feed) { !$0.isLoading }
        XCTAssertEqual(viewModel.displayedCount, 5)

        viewModel.loadNextPage()
        XCTAssertEqual(viewModel.displayedCount, 10)

        viewModel.loadNextPage()
        XCTAssertEqual(viewModel.displayedCount, 15)
        XCTAssertEqual(viewModel.displayedTweets.map(\.id), viewModel.allTweets.map(\.id))
    }

    /// FR-PAGE-003: reaching the end must not overrun or error. The trigger is an `.onAppear` on
    /// the last row, which fires again whenever that row is scrolled back into view, so this is
    /// the real production path rather than a defensive extra.
    func test_appending_at_the_end_is_idempotent() {
        let viewModel = makeViewModel()

        viewModel.loadInitialData()
        awaitPublished(viewModel.$feed) { !$0.isLoading }
        viewModel.loadNextPage()
        viewModel.loadNextPage()
        XCTAssertEqual(viewModel.displayedCount, 15)

        viewModel.loadNextPage()
        viewModel.loadNextPage()

        XCTAssertEqual(viewModel.displayedCount, 15, "The window must not grow past the feed.")
        XCTAssertEqual(viewModel.displayedTweets.count, viewModel.allTweets.count)
    }

    /// The window can never promise rows the feed does not have. With nothing loaded `allTweets`
    /// is empty, so the `min` pins the count at 0 rather than at a page size.
    func test_appending_before_the_feed_lands_does_nothing() {
        let viewModel = makeViewModel()

        viewModel.loadNextPage()

        XCTAssertEqual(viewModel.displayedCount, 0)
        XCTAssertTrue(viewModel.displayedTweets.isEmpty)
    }

    // MARK: - Refreshing (FR-PAGE-004/006)

    /// The requirement itself, and `nfr §4.5`'s acceptance sequence completed: 5 → 10 → 15 → 5.
    func test_refresh_resets_the_window_to_the_first_page() async {
        let viewModel = makeViewModel()

        viewModel.loadInitialData()
        awaitPublished(viewModel.$feed) { !$0.isLoading }
        viewModel.loadNextPage()
        viewModel.loadNextPage()
        XCTAssertEqual(viewModel.displayedCount, 15)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.displayedCount, 5)
        XCTAssertEqual(viewModel.displayedTweets.count, 5)
        XCTAssertEqual(viewModel.allTweets.count, 15, "The whole feed is still held (FR-FEED-001).")
    }

    /// FR-PAGE-006 resolved toward re-fetching, and both endpoints rather than the feed alone:
    /// either request can be the one that failed (`FR-FEED-005`), so a feed-only refresh would
    /// leave a user who launched offline with a permanently broken header.
    func test_refresh_re_requests_both_endpoints() async {
        let feed = MockBaseService(result: .success(feedFixture))
        let profile = MockBaseService(json: Self.profileJson)
        let viewModel = makeViewModel(feed: feed, profile: profile)

        viewModel.loadInitialData()
        awaitPublished(viewModel.$feed) { !$0.isLoading }
        XCTAssertEqual(feed.callCount, 1)

        await viewModel.refresh()

        XCTAssertEqual(feed.callCount, 2)
        XCTAssertEqual(profile.callCount, 2)
    }

    /// Re-fetching means the new payload wins. The window follows it down to 2 rather than
    /// padding to a page — `fn-spec §8 Q6` on the refresh path, free, because `apply(feed:)` is
    /// the same assignment the initial load makes.
    func test_refresh_picks_up_changed_data() async {
        let feed = MockBaseService(result: .success(feedFixture))
        let viewModel = makeViewModel(feed: feed)

        viewModel.loadInitialData()
        awaitPublished(viewModel.$feed) { !$0.isLoading }
        XCTAssertEqual(viewModel.allTweets.count, 15)

        feed.result = .success(Data("""
        [{"content": "one", "sender": {"nick": "A"}}, {"content": "two", "sender": {"nick": "B"}}]
        """.utf8))
        await viewModel.refresh()

        XCTAssertEqual(viewModel.allTweets.count, 2)
        XCTAssertEqual(viewModel.displayedCount, 2, "No padding to a full page.")
        XCTAssertEqual(viewModel.displayedTweets.first?.content, "one")
    }

    /// The headline behaviour: launch with the backend down, start it, pull to refresh. This is
    /// the recovery path `nfr §2.13` conceded was missing until `FR-PAGE-004` landed, which is
    /// what decided `fn-spec §8 Q2` — a reset-only refresh recovers nothing here.
    func test_refresh_recovers_a_failed_feed() async throws {
        let feed = MockBaseService(result: .failure(.transport(URLError(.notConnectedToInternet))))
        let viewModel = makeViewModel(feed: feed)

        viewModel.loadInitialData()
        awaitPublished(viewModel.$feed) { !$0.isLoading }
        XCTAssertNotNil(viewModel.feedError)
        XCTAssertEqual(viewModel.displayedCount, 0)

        feed.result = .success(feedFixture)
        await viewModel.refresh()

        XCTAssertNil(viewModel.feedError, "A successful refresh clears the error state.")
        XCTAssertEqual(viewModel.displayedCount, 5)
        XCTAssertEqual(viewModel.allTweets.count, 15)
    }

    /// FR-FEED-002 survives the refresh. `refresh()` takes a second entry path rather than
    /// relaxing `loadInitialData()`'s `.idle` guard, so the guard still holds afterwards: the
    /// states are `.loaded` or `.failed`, never back to `.idle`.
    func test_a_load_after_a_refresh_still_does_not_request_again() async {
        let feed = MockBaseService(result: .success(feedFixture))
        let profile = MockBaseService(json: Self.profileJson)
        let viewModel = makeViewModel(feed: feed, profile: profile)

        viewModel.loadInitialData()
        awaitPublished(viewModel.$feed) { !$0.isLoading }
        await viewModel.refresh()
        XCTAssertEqual(feed.callCount, 2)

        viewModel.loadInitialData()

        XCTAssertEqual(feed.callCount, 2, "The .idle guard still holds after a refresh.")
        XCTAssertEqual(profile.callCount, 2)
    }

    // MARK: - Loading (FR-FEED-003)

    /// The defect this commit exists to fix: the flag must follow real in-flight work. The code it
    /// replaces toggled twice before either request had started, then once more per completion.
    func test_the_indicator_is_shown_while_in_flight_and_hidden_once_settled() {
        let viewModel = makeViewModel()

        XCTAssertFalse(viewModel.showIndicator, "Nothing has been requested yet.")

        viewModel.loadInitialData()
        XCTAssertTrue(viewModel.showIndicator, "Both requests are in flight.")

        awaitPublished(viewModel.$feed) { !$0.isLoading }
        awaitPublished(viewModel.$profile) { !$0.isLoading }
        XCTAssertFalse(viewModel.showIndicator)
    }

    /// FR-FEED-003 names the failure case explicitly — an indicator that never stops is the
    /// symptom `fn-spec §7`'s offline criterion forbids.
    func test_the_indicator_is_hidden_when_both_requests_fail() {
        let viewModel = makeViewModel(
            feed: .init(result: .failure(.httpStatus(500))),
            profile: .init(result: .failure(.httpStatus(500)))
        )

        viewModel.loadInitialData()
        awaitPublished(viewModel.$feed) { !$0.isLoading }
        awaitPublished(viewModel.$profile) { !$0.isLoading }

        XCTAssertFalse(viewModel.showIndicator)
    }

    // MARK: - Errors (FR-FEED-004, NFR-DATA-005)

    /// The error survives as a typed value the view can render, rather than being printed.
    func test_a_failed_feed_surfaces_a_typed_error_and_shows_no_tweets() throws {
        let viewModel = makeViewModel(feed: .init(result: .failure(.httpStatus(404))))

        viewModel.loadInitialData()
        awaitPublished(viewModel.$feed) { !$0.isLoading }

        XCTAssertHttpStatus(try XCTUnwrap(viewModel.feedError), 404)
        XCTAssertTrue(viewModel.displayedTweets.isEmpty)
        XCTAssertEqual(viewModel.displayedCount, 0)
    }

    // MARK: - Independence (FR-FEED-005)

    func test_a_failed_profile_does_not_blank_the_feed() {
        let viewModel = makeViewModel(profile: .init(result: .failure(.transport(URLError(.notConnectedToInternet)))))

        viewModel.loadInitialData()
        awaitPublished(viewModel.$feed) { !$0.isLoading }
        awaitPublished(viewModel.$profile) { !$0.isLoading }

        XCTAssertEqual(viewModel.displayedTweets.count, 5)
        XCTAssertNil(viewModel.feedError, "A profile failure is not a feed error.")
        XCTAssertNil(viewModel.user)
    }

    func test_a_failed_feed_does_not_blank_the_profile() throws {
        let viewModel = makeViewModel(feed: .init(result: .failure(.httpStatus(500))))

        viewModel.loadInitialData()
        awaitPublished(viewModel.$feed) { !$0.isLoading }
        awaitPublished(viewModel.$profile) { !$0.isLoading }

        XCTAssertEqual(try XCTUnwrap(viewModel.user).nick, "Huan Huan")
        XCTAssertNotNil(viewModel.feedError)
    }

    // MARK: - Idempotence (FR-FEED-002, NFR-PERF-008)

    /// `.onAppear` fires again on every rebuild of the row and on return from the background. A
    /// second request would re-fetch the feed and reset the window under the user.
    func test_a_second_load_does_not_request_again() {
        let feed = MockBaseService(result: .success(feedFixture))
        let profile = MockBaseService(json: Self.profileJson)
        let viewModel = makeViewModel(feed: feed, profile: profile)

        viewModel.loadInitialData()
        awaitPublished(viewModel.$feed) { !$0.isLoading }
        viewModel.loadInitialData()

        XCTAssertEqual(feed.callCount, 1)
        XCTAssertEqual(profile.callCount, 1)
    }

    // MARK: - Helpers

    private static let profileJson = """
    {"profile-image": "https://example.invalid/p.jpeg", "avatar": "https://example.invalid/a.png",
     "nick": "Huan Huan", "username": "hengzeng"}
    """

    private func makeViewModel(
        feed: MockBaseService? = nil,
        profile: MockBaseService? = nil
    ) -> MomentsViewModel {
        MomentsViewModel(
            tweetService: TweetService(httpService: feed ?? MockBaseService(result: .success(feedFixture))),
            userService: UserService(httpService: profile ?? MockBaseService(json: Self.profileJson))
        )
    }
}
