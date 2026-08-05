//
//  MomentView.swift
//  WeChatMoments
//
//  Created by Tushar Sharma on 22/02/24.
//

import SwiftUI

struct MomentView: View {
    // arch-spec §4.1: @StateObject, not @ObservedObject. With @ObservedObject SwiftUI does not own
    // the object's lifetime, so a structural re-render of the parent builds a fresh view model —
    // discarding the loaded feed and resetting the pagination window (FR-PAGE-001) under the user.
    @StateObject private var momentsViewModel = MomentsViewModel()

    private var indicatorView:some View {
        return ProgressView()
            .progressViewStyle(CircularProgressViewStyle())
            .controlSize(.large)
    }

    /// FR-PAGE-001/005: the window is the view model's, already derived. The view does no paging
    /// arithmetic of its own.
    private var tweets:[Tweet] {
        return momentsViewModel.displayedTweets
    }

    private var user: User? {
        return momentsViewModel.user
    }

    /// FR-PAGE-002/005: the view decides *when* to page, the view model decides *what* that means.
    /// Deliberately unguarded beyond the identity check — `loadNextPage()` clamps, so the cost of
    /// this firing again on a row that is scrolled back into view is an assignment (`FR-PAGE-003`).
    private func appendPageIfLast(_ tweet: Tweet) {
        guard tweet.id == tweets.last?.id else { return }
        momentsViewModel.loadNextPage()
    }

    var body: some View {
        List {
            Group {
                HeaderView(user: user)
                // FR-FEED-004: a failed feed reads as a message where the tweets would be, not as
                // an empty list. It sits below the header because the profile request is
                // independent and may well have succeeded (FR-FEED-005).
                if let error = momentsViewModel.feedError {
                    FeedErrorView(error: error)
                }
                // NFR-DATA-007: Tweet carries its own stable id; \.self would collide
                // on duplicate content.
                ForEach(tweets) { tweet in
                    // One List row per tweet. The separator has to live *inside* the row: as a
                    // sibling of TweetView it became a row of its own, and a List row has a
                    // minimum height, so the hairline reserved ~44pt of empty space under every
                    // cell. The ad-hoc Divider that stood here had the same problem.
                    VStack(spacing: 0) {
                        TweetView(tweet: tweet)
                        FooterView()   // FR-TWEET-008
                    }
                    // FR-PAGE-002: List is lazy, so a row's .onAppear is the moment it scrolls
                    // into view. fn-spec §8 Q1 resolved to the last cell merely becoming visible.
                    .onAppear { appendPageIfLast(tweet) }
                }
                .listRowSeparator(.hidden)
            }
            .listRowInsets(EdgeInsets())
        }
        .listStyle(PlainListStyle())
        .overlay(content: {
            if momentsViewModel.showIndicator {
                indicatorView
            }
        })
        // FR-PAGE-004: the gesture is the system's, the transition is the view model's. No
        // app-level indicator is needed — .refreshable holds its own spinner until this
        // returns (fn-spec §8 Q4).
        .refreshable {
            await momentsViewModel.refresh()
        }
        .onAppear {
            // Idempotent by design — .onAppear fires again on every rebuild of this row and on
            // return from the background (FR-FEED-002).
            momentsViewModel.loadInitialData()
        }
        // NFR-LAYOUT-006: the bottom edge still bleeds, but the top is left to the safe area so
        // the .refreshable spinner draws below the status bar where it can be seen. A blanket
        // .ignoresSafeArea() put it under the clock.
        // NFR-LAYOUT-006: the top edge is left to the safe area so the .refreshable spinner draws
        // below the status bar instead of inside it. Verified both ways under a held pull — with
        // a blanket .ignoresSafeArea() the spinner lands beside the clock. The cost is that the
        // banner no longer bleeds under the status bar, which FR-HEADER-001's reference
        // screenshot does show; see the summary for the alternative.
        .ignoresSafeArea(edges: .bottom)
    }
}

#Preview {
    MomentView()
}
