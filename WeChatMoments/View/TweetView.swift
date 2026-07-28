//
//  TweetView.swift
//  WeChatMoments
//
//  Created by Wole Solana on 2/28/24.
//

import SwiftUI

struct TweetView: View {
    var tweet: Tweet

    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                // TODO: FR-TWEET-001 — the sender's real avatar. `tweet.sender.avatar` exists
                // since commit 01; wiring it is commit 05's scope, not this one's.
                RemoteImage(urlString: nil, targetSize: Constants.SENDER_AVATAR_SIZE)
                    .frame(
                        width: Constants.SENDER_AVATAR_SIZE.width,
                        height: Constants.SENDER_AVATAR_SIZE.height)
                    .cornerRadius(5.0)

                // TODO: FR-TWEET-001 — the sender's real nick, likewise commit 05.
                VStack(alignment: .leading) {
                    Text("Placeholder Profile")
                        .font(.system(size: Constants.FONT_SIZE_CONTENT))
                        .foregroundColor(.blue)

                    Text(tweet.content ?? "")
                        .foregroundColor(.black)
                        .font(.system(size: Constants.FONT_SIZE_CONTENT))
                        .lineLimit(nil)
                        .padding(.top, Constants.TWEET_CONTENT_TOP_OFFSET)

                    // TODO: FR-TWEET-004/005 — the 0-to-9 image grid, commit 06. The helper that
                    // stood here (`addImagesToView(_from:)`) rendered a fixed 0..<5 range and
                    // ended in `.padding() as? AnyView`, a cast that always evaluated to nil, so
                    // it never drew anything. fn-spec §4.4: rewrite, do not patch.
                }
                .padding(.leading, Constants.TWEET_SENDER_LEFT_OFFSET)

                Spacer()
            }
        }
        .padding([.leading, .trailing], Constants.TWEET_SENDER_LEFT_OFFSET)
    }
}

#Preview {
    TweetView(
        tweet: Tweet(
            sender: User(
                username: "wfan",
                nick: "Wei Fan",
                avatar: "https://techops-recsys-lateral-hiring.github.io/moments-data/images/user/avatar/005.jpeg",
                profile: nil
            ),
            content: "Unlike many proprietary big data processing platform different, Spark is built on a unified abstract RDD, making it possible to deal with different ways consistent with large data processing scenarios, including MapReduce, Streaming, SQL, Machine Learning and Graph so on. To understand the Spark, you have to understand the RDD.",
            images: nil,
            comments: nil
        )
    )
    .environment(\.imageLoader, MockImageLoader())
}
