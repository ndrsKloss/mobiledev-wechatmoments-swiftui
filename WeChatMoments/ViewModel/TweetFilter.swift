//
//  TweetFilter.swift
//  WeChatMoments
//
//  A pure transform over the decoded feed (NFR-TEST-006), applied once at the boundary where
//  the feed enters memory (FR-DATA-004) so that the pagination window addresses only tweets
//  that will actually be drawn.
//

import Foundation

enum TweetFilter {

    /// FR-DATA-001/002: a tweet is displayable when it has content **or** images. Only a tweet
    /// with neither is dropped.
    ///
    /// The rule this replaces was `$0.content != nil` — a narrower proxy that reads as
    /// reasonable and silently discarded all four image-only tweets in the served feed.
    static func isDisplayable(_ tweet: Tweet) -> Bool {
        let hasContent = tweet.content?.isEmpty == false
        let hasImages = tweet.images?.isEmpty == false
        return hasContent || hasImages
    }

    /// Order is preserved; `FR-DATA-004` makes the result the sole basis for paging indices.
    static func displayable(_ tweets: [Tweet]) -> [Tweet] {
        tweets.filter(isDisplayable)
    }
}
