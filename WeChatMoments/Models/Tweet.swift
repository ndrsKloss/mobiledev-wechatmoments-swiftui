//
//  Tweet.swift
//  WeChatMoments
//

import Foundation

/// One element of the moments feed.
///
/// `sender` is non-optional: every well-formed element in the data contract carries one
/// (`fn-spec §3.2`). That is deliberate — it is what makes the feed's malformed elements
/// fail to decode, which in turn is what makes the per-element tolerance in `TweetService`
/// load-bearing rather than decorative (`NFR-DATA-001`).
struct Tweet: Decodable, Identifiable {
    // NFR-DATA-007 / FAD-DATA-d: the payload carries no id, so identity is assigned client-side.
    let id = UUID()
    let sender: User
    let content: String?
    let images: [Img]?
    let comments: [Comment]?

    // `id` is excluded: it has a default value and is not part of the wire format (FR-API-003).
    private enum CodingKeys: String, CodingKey {
        case sender, content, images, comments
    }
}
