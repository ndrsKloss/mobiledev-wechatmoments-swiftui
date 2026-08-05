//
//  MomentsViewModel.swift
//  WeChatMoments
//
//  Created by Tushar Sharma on 19/03/24.
//

import Foundation
import Combine

final class MomentsViewModel: ObservableObject {

    private let tweetService: TweetService
    private let userService: UserService
    private var cancellables = Set<AnyCancellable>()

    /// The full decoded, filtered feed (`FR-FEED-001`) and the profile, each carrying its own
    /// lifecycle so one failure cannot take the other down (`FR-FEED-005`).
    @Published private(set) var feed: Loadable<[Tweet]> = .idle
    @Published private(set) var profile: Loadable<User> = .idle

    /// How many of the feed are currently shown. `arch-spec §7.1`: the window is this number plus
    /// a `prefix`, never a second stored array — two arrays would need keeping in sync for no gain.
    @Published private(set) var displayedCount = 0

    // NFR-TEST-001 / arch-spec §4.2: the services arrive by injection instead of being constructed
    // in a stored-property initialiser. No new protocol — `TweetService` and `UserService` perform
    // no I/O themselves, they compose the already-injectable `BaseService`, and `arch-spec §6`
    // forbids abstracting past the seam that buys the testability.
    init(tweetService: TweetService = TweetService(),
         userService: UserService = UserService()) {
        self.tweetService = tweetService
        self.userService = userService
    }

    // MARK: - Derived state

    var user: User? { profile.value }

    /// FR-FEED-001: the whole feed stays in memory; scrolling never re-requests it (`FR-FEED-002`).
    var allTweets: [Tweet] { feed.value ?? [] }

    /// FR-PAGE-001/005, NFR-PERF-008: the displayed window, derived. `prefix` clamps on its own, so
    /// a feed shorter than a page renders what exists with no padding (`fn-spec §8 Q6`).
    var displayedTweets: [Tweet] { Array(allTweets.prefix(displayedCount)) }

    /// FR-FEED-003: true exactly while a request is in flight. The flag it replaces was toggled
    /// twice before either request had started and once more per completion, so it tracked nothing.
    var showIndicator: Bool { feed.isLoading || profile.isLoading }

    /// FR-FEED-004: what the view renders instead of an empty list.
    var feedError: NetworkError? { feed.error }

    // MARK: - Intents

    /// `arch-spec §7.3`: fetch, filter, store the full feed; set the displayed count to one page.
    ///
    /// FR-FEED-002: guarded on `.idle` because `.onAppear` fires again whenever the row is rebuilt
    /// or the app returns from the background. Without the guard every one of those would re-request
    /// the feed and reset the window under the user.
    func loadInitialData() {
        guard feed.isIdle, profile.isIdle else { return }

        feed = .loading
        profile = .loading
        loadTweets()
        loadUserProfile()
    }

    /// `arch-spec §7.3`, FR-PAGE-002: grow the window by one page over the feed already in memory.
    ///
    /// FR-PAGE-003 lives in the `min`. At the end of the list this assigns the value the property
    /// already holds, so a trigger that fires more than once is a no-op rather than an overrun —
    /// which is what lets the view trigger stay a single unguarded comparison. No network
    /// (`NFR-PERF-008`): holding the whole feed in commit 06 is what buys that.
    func loadNextPage() {
        displayedCount = min(displayedCount + Constants.PAGE_SIZE, allTweets.count)
    }

    /// `arch-spec §7.3`, FR-PAGE-004: re-request both endpoints and reset the window to one page.
    ///
    /// FR-PAGE-006 / `fn-spec §8 Q2` resolved toward re-fetching. A reset-only refresh recovers
    /// nothing over a `.failed` feed — `allTweets` is empty, so resetting the count to 5 gives you
    /// five of nothing — and this is the app's only recovery affordance (`nfr §2.13`).
    ///
    /// It deliberately does *not* call `loadInitialData()`: that method's `.idle` guard is the
    /// whole implementation of `FR-FEED-002`, and relaxing it so this could reuse it would cost
    /// the requirement the guard exists to enforce.
    ///
    /// Nothing is set to `.loading` (`fn-spec §8 Q4`, revisited for this path): `.refreshable`
    /// already shows a spinner, `showIndicator` would stack the app's full-screen one on top of
    /// it, and blanking `allTweets` would empty the list under the user's own finger. The old
    /// content stays until the new content replaces it.
    @MainActor
    func refresh() async {
        async let feedOutcome = Self.firstOutcome(tweetService.getTweets(Constants.USER_NAME))
        async let profileOutcome = Self.firstOutcome(userService.getUserProfile(Constants.USER_NAME))

        apply(feed: await feedOutcome)
        apply(profile: await profileOutcome)
    }

    // MARK: - State transitions

    /// The one place the feed and the window are assigned. FR-PAGE-001 ("show the first 5 on
    /// load") and FR-PAGE-004 ("reset to the first 5 on refresh") are not two behaviours kept
    /// consistent — they are the same assignment reached from two entry points.
    private func apply(feed outcome: Result<[Tweet], NetworkError>) {
        switch outcome {
        case let .success(tweets):
            // FR-DATA-001/002/004: filtered once, here, where the feed enters memory, so the
            // window addresses only tweets that will actually be drawn.
            let displayable = TweetFilter.displayable(tweets)
            feed = .loaded(displayable)
            displayedCount = min(Constants.PAGE_SIZE, displayable.count)   // FR-PAGE-001/004
        case let .failure(error):
            feed = .failed(error)
        }
    }

    private func apply(profile outcome: Result<User, NetworkError>) {
        switch outcome {
        case let .success(user):
            profile = .loaded(user)
        case let .failure(error):
            // FR-FEED-005: recorded, not rendered as a screen-level error. A missing profile is
            // FR-HEADER-002's placeholder case, not a reason to hide the feed.
            profile = .failed(error)
        }
    }

    // MARK: - Requests

    private func loadTweets() {
        tweetService.getTweets(Constants.USER_NAME)
            .receive(on: RunLoop.main)   // NFR-PERF-004
            .sink { [weak self] completion in
                if case let .failure(error) = completion {
                    self?.apply(feed: .failure(error))
                }
            } receiveValue: { [weak self] tweets in
                self?.apply(feed: .success(tweets))
            }.store(in: &cancellables)
    }

    private func loadUserProfile() {
        userService.getUserProfile(Constants.USER_NAME)
            .receive(on: RunLoop.main)
            .sink { [weak self] completion in
                if case let .failure(error) = completion {
                    self?.apply(profile: .failure(error))
                }
            } receiveValue: { [weak self] user in
                self?.apply(profile: .success(user))
            }.store(in: &cancellables)
    }

    /// The Combine → async seam `.refreshable` requires, as six lines rather than a type.
    ///
    /// `arch-spec §6` forbids a protocol with one implementation and no test double, and that is
    /// all a `Refreshing` abstraction would be. `values` exposes any publisher as an async
    /// sequence and these publishers emit exactly one value or fail, so there is no continuation
    /// to resume twice and no `AnyCancellable` to keep alive by hand. `static` so it cannot
    /// capture `self`, which keeps the `async let` pair uncomplicated.
    private static func firstOutcome<Value>(
        _ publisher: AnyPublisher<Value, NetworkError>
    ) async -> Result<Value, NetworkError> {
        do {
            for try await value in publisher.values {
                return .success(value)
            }
            // Unreachable for these two publishers, which always emit or fail. A result on every
            // path regardless — the alternative is a refresh that silently leaves the old state.
            return .failure(.invalidResponse)
        } catch let error as NetworkError {
            return .failure(error)
        } catch {
            return .failure(.decoding(error))
        }
    }
}
