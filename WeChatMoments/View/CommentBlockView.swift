//
//  CommentBlockView.swift
//  WeChatMoments
//

import SwiftUI

/// The comment block under a tweet's content (FR-TWEET-006/007).
///
/// It owns the "absent *or empty* renders nothing at all" rule. That distinction is load-bearing:
/// two elements in the served feed carry `"comments": []`, and an empty `VStack` would still
/// contribute its enclosing stack's spacing and its own background fill — a grey sliver under a
/// tweet that has no comments. The `if` is the requirement.
struct CommentBlockView: View {
    var comments: [Comment]?

    var body: some View {
        if let comments, !comments.isEmpty {
            VStack(alignment: .leading, spacing: Constants.COMMENT_ROW_SPACING) {
                // `Comment` carries no identity of its own and this is a static stack scoped to
                // one tweet, so positional identity is stable here. NFR-DATA-007 governs the
                // feed `List`, which keys on `Tweet.id`.
                ForEach(comments.indices, id: \.self) { index in
                    CommentRowView(comment: comments[index])
                }
            }
            .padding(Constants.COMMENT_BLOCK_PADDING)
            // FR-TWEET-007: the block sits on its own fill, rather than each Text carrying one.
            .background(Color.commentsBackgroudColor)
        }
    }
}

#Preview {
    VStack(alignment: .leading) {
        CommentBlockView(comments: [
            Comment(
                content: "Nice shot.",
                sender: User(username: "lhuang", nick: "Lei Huang", avatar: nil, profile: nil)
            ),
            Comment(
                content: "Where was this taken?",
                sender: User(username: "cyao", nick: "Cheng Yao", avatar: nil, profile: nil)
            )
        ])

        Text("↓ an empty array and an absent one both render nothing below this line")
            .font(.footnote)
        CommentBlockView(comments: [])
        CommentBlockView(comments: nil)
    }
    .padding()
}
