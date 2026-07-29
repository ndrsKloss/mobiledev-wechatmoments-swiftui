//
//  TweetView.swift
//  WeChatMoments
//
//  Created by Wole Solana on 2/28/24.
//

import SwiftUI

/// One cell of the feed: sender avatar and nick, then whichever of content, images and comments
/// the tweet actually carries (fn-spec §2, region 2).
///
/// Every element below the nick is conditional. That is the requirement, not a nicety — a tweet
/// with no content must not leave an empty text row behind it (FR-TWEET-002), and one with no
/// comments must not leave a grey sliver (FR-TWEET-006).
struct TweetView: View {
    var tweet: Tweet

    var body: some View {
        HStack(alignment: .top, spacing: Constants.TWEET_SENDER_LEFT_OFFSET) {
            // FR-TWEET-001 / NFR-DATA-004: a missing or failed avatar is the placeholder asset,
            // which RemoteImage handles; nothing here force-unwraps.
            RemoteImage(urlString: tweet.sender.avatar, targetSize: Constants.SENDER_AVATAR_SIZE)
                .frame(
                    width: Constants.SENDER_AVATAR_SIZE.width,
                    height: Constants.SENDER_AVATAR_SIZE.height)
                .clipShape(.rect(cornerRadius: 5))

            VStack(alignment: .leading, spacing: Constants.TWEET_CONTENT_TOP_OFFSET) {
                // FR-TWEET-001: the sender's real nick, with the fallback chain in
                // User+DisplayName — every field of the payload's user is optional.
                Text(tweet.sender.displayName)
                    .font(.system(size: Constants.FONT_SIZE_CONTENT))
                    .foregroundStyle(.blue)

                // FR-TWEET-002: no content, no row. FR-TWEET-003: wraps to as many lines as it
                // needs — `fixedSize` is what stops the List row from truncating it to one.
                if let content = tweet.content, !content.isEmpty {
                    Text(content)
                        .font(.system(size: Constants.FONT_SIZE_CONTENT))
                        .foregroundStyle(.black)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // FR-TWEET-004/005: 0 to 9 images, laid out per fn-spec §5. Absent or empty
                // renders nothing at all — the grid owns that rule, as the comment block does.
                ImageGridView(images: tweet.images)

                // FR-TWEET-006: absent or empty comments render nothing at all.
                CommentBlockView(comments: tweet.comments)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Constants.TWEET_SENDER_LEFT_OFFSET)
        .padding(.vertical, Constants.TWEET_VERTICAL_PADDING)
    }
}

// The four shapes fn-spec §7 asks to see: text-only, image-only, with comments, and with an
// empty comments array. The image-only case is the one the FR-DATA-002 filter fix restores.
#Preview("Text only") {
    TweetView(tweet: .previewTextOnly)
        .environment(\.imageLoader, MockImageLoader())
}

#Preview("No content") {
    TweetView(tweet: .previewImageOnly)
        .environment(\.imageLoader, MockImageLoader())
}

#Preview("With comments") {
    TweetView(tweet: .previewWithComments)
        .environment(\.imageLoader, MockImageLoader())
}

#Preview("Empty comments") {
    TweetView(tweet: .previewEmptyComments)
        .environment(\.imageLoader, MockImageLoader())
}

// The two fn-spec §5 rows tagged [A]. Both sit below the fold in the running feed — one 4-image
// tweet and one 9-image tweet out of fifteen — so this is where they get looked at.
#Preview("Four images") {
    TweetView(tweet: .previewImages(4))
        .environment(\.imageLoader, MockImageLoader())
}

#Preview("Nine images") {
    TweetView(tweet: .previewImages(9))
        .environment(\.imageLoader, MockImageLoader())
}

#if DEBUG
private extension Tweet {
    static let previewSender = User(
        username: "wfan",
        nick: "Wei Fan",
        avatar: "https://techops-recsys-lateral-hiring.github.io/moments-data/images/user/avatar/005.jpeg",
        profile: nil
    )

    static let previewTextOnly = Tweet(
        sender: previewSender,
        content: "Unlike many proprietary big data processing platform different, Spark is built on a unified abstract RDD, making it possible to deal with different ways consistent with large data processing scenarios, including MapReduce, Streaming, SQL, Machine Learning and Graph so on. To understand the Spark, you have to understand the RDD.",
        images: nil,
        comments: nil
    )

    static let previewImageOnly = Tweet(
        sender: previewSender,
        content: nil,
        images: [Img(url: "https://example.invalid/1.jpeg")],
        comments: nil
    )

    static let previewWithComments = Tweet(
        sender: previewSender,
        content: "First post!",
        images: nil,
        comments: [
            Comment(
                content: "Nice shot.",
                sender: User(username: "lhuang", nick: "Lei Huang", avatar: nil, profile: nil)
            ),
            Comment(
                content: "Where was this taken?",
                sender: User(username: "cyao", nick: "Cheng Yao", avatar: nil, profile: nil)
            )
        ]
    )

    static func previewImages(_ count: Int) -> Tweet {
        Tweet(
            sender: previewSender,
            content: "\(count) images.",
            images: (0..<count).map { Img(url: "https://example.invalid/\($0).jpeg") },
            comments: nil
        )
    }

    static let previewEmptyComments = Tweet(
        sender: previewSender,
        content: "This one has an empty comments array and must render no block.",
        images: nil,
        comments: []
    )
}
#endif
