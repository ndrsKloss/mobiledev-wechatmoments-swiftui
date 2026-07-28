//
//  CommentRowView.swift
//  WeChatMoments
//
//  Created by Wole Solana on 2/27/24.
//

import SwiftUI

/// One line of the comment block: the commenter's nick, tinted, then the comment (FR-TWEET-007).
///
/// The nick and the text are a single `Text` rather than two in an `HStack`, so a long comment
/// wraps as one paragraph and re-flows with the available width (NFR-LAYOUT-001/004). The row
/// carries no `Button`: fn-spec §6 states the page is static, and a tappable nick was the only
/// thing on the screen suggesting otherwise.
struct CommentRowView: View {
    var comment: Comment

    var body: some View {
        let nick = Text(comment.sender.displayName)
            .foregroundStyle(.blue)
        let content = Text(": \(comment.content ?? "")")
            .foregroundStyle(.black)

        Text("\(nick)\(content)")
            .font(.system(size: Constants.FONT_SIZE_COMMENT))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Constants.COMMENT_ROW_SPACING) {
        CommentRowView(
            comment: Comment(
                content: "Some Comment",
                sender: User(username: "test user", nick: nil, avatar: nil, profile: nil)
            )
        )
        CommentRowView(
            comment: Comment(
                content: "A comment long enough to prove that the nick and the text wrap "
                    + "together as one paragraph rather than clipping to a single line.",
                sender: User(username: "lhuang", nick: "Lei Huang", avatar: nil, profile: nil)
            )
        )
        // Both fields absent — FR-API-002 says every user field is optional.
        CommentRowView(comment: Comment(content: nil, sender: nil))
    }
    .padding()
    .background(Color.commentsBackgroudColor)
}
