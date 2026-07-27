//
//  User.swift
//  WeChatMoments
//

import Foundation

/// The profile owner, and the sender of a tweet or a comment.
///
/// Every field is optional (`FR-API-002`); a missing one renders a fallback, never a crash.
struct User: Decodable {
    let username: String?
    let nick: String?
    let avatar: String?
    let profile: String?

    // FR-API-001: the wire key is hyphenated and cannot be a Swift identifier.
    private enum CodingKeys: String, CodingKey {
        case username, nick, avatar
        case profile = "profile-image"
    }
}
