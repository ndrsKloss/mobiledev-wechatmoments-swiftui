//
//  User+DisplayName.swift
//  WeChatMoments
//
//  The name a tweet's sender (FR-TWEET-001) and a comment's sender (FR-TWEET-007) are shown
//  under. It lives here rather than on the model itself because arch-spec §3 keeps
//  presentation logic out of `Models/`, and here rather than duplicated in two views because
//  it was already duplicated once — `CommentRowView` carried a private copy.
//

import Foundation

extension User {
    /// FR-API-002: every field is optional, so the fallback chain needs a final rung.
    var displayName: String {
        if let nick, !nick.isEmpty { return nick }
        if let username, !username.isEmpty { return username }
        return "Unknown"
    }
}

extension Optional where Wrapped == User {
    /// `Comment.sender` is optional (fn-spec §3.2); an absent sender is as nameless as a
    /// present one with no fields.
    var displayName: String {
        self?.displayName ?? "Unknown"
    }
}
