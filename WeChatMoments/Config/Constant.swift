//
//  Constant.swift
//  WeChatMoments
//
//  Created by nontapat.siengsanor on 23/2/24.
//

import Foundation

enum Constants {
    static let USER_NAME = "jsmith"
    static let DEFAULT_EMPTY_IMAGE = "emptyImage"

    /// FR-PAGE-001/002/004, arch-spec §7.3 and §9: the page size lives here rather than as a
    /// literal in the view model, because three separate requirements quote the same 5.
    static let PAGE_SIZE = 5

    static let FONT_SIZE_COMMENT: CGFloat = 12
    static let FONT_SIZE_CONTENT: CGFloat = 15
    static let SENDER_AVATAR_SIZE = CGSize(width: 40, height: 40)
    static let SENDER_PROFILE_SIZE = CGSize(width: 75, height: 75)
    static let IMAGE_SIZE = CGSize(width: 82, height: 82)
    static let TWEET_AVATAR_OFFSET: CGFloat = 5
    static let TWEET_SENDER_LEFT_OFFSET: CGFloat = 15
    static let TWEET_CONTENT_TOP_OFFSET: CGFloat = 6
    static let TWEET_IMAGE_SEPARATOR_SPACE: CGFloat = 5
    static let TWEET_VERTICAL_PADDING: CGFloat = 12
    static let COMMENT_ROW_SPACING: CGFloat = 2
    static let COMMENT_BLOCK_PADDING: CGFloat = 6
    static let SEPARATOR_HEIGHT: CGFloat = 0.5
}
