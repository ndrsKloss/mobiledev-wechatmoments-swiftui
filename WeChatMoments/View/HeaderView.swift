//
//  HeaderView.swift
//  WeChatMoments
//
//  Created by Tushar Sharma on 09/03/24.
//

import SwiftUI

struct HeaderView: View {
    private let avatarImageWidth: CGFloat = 75
    private let avatarImageHeight: CGFloat = 75

    private let nickNameLabelWidth: CGFloat = 200
    private let nickNameFontSize: CGFloat = 16

    private let headerViewHeight: CGFloat = 370

    var user: User?

    /// Derived from `user`, so it is not @State. Storing it in @State — as this view used to —
    /// makes the view the owner of a value it does not own, and the copy goes stale the moment
    /// `user` arrives a second time.
    private var nickname: String { user?.nick ?? "" }

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                // The banner is downsampled to the space it actually occupies, not to
                // Constants.SENDER_PROFILE_SIZE (75×75) as the old loader was asked for — that
                // would have thumbnailed a full-bleed cover image to avatar size.
                RemoteImage(
                    urlString: user?.profile,
                    targetSize: CGSize(width: proxy.size.width, height: headerViewHeight)
                )
                .frame(width: proxy.size.width, height: headerViewHeight)
                .clipped()

                HStack(spacing: 20) {
                    Text(nickname)
                        .frame(width: nickNameLabelWidth, alignment: .trailing)
                        .font(.system(size: nickNameFontSize, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.bottom, 15)

                    RemoteImage(
                        urlString: user?.avatar,
                        targetSize: CGSize(width: avatarImageWidth, height: avatarImageHeight)
                    )
                    .frame(width: avatarImageWidth, height: avatarImageHeight)
                    .cornerRadius(5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(.white, lineWidth: 2)
                    )
                }.offset(x: avatarImageXOffset(from: proxy), y: avatarImageYOffset())
            }
        }.frame(height: headerViewHeight + 28)
    }

    private func avatarImageXOffset(from proxy: GeometryProxy) -> CGFloat {
        let padding: CGFloat = 30
        let avatarImageXAxis: CGFloat = nickNameLabelWidth + avatarImageWidth + padding
        return proxy.size.width - avatarImageXAxis
    }

    private func avatarImageYOffset() -> CGFloat {
        let padding: CGFloat = 50
        return headerViewHeight - padding
    }
}

#Preview {
    HeaderView(user: User(username: "jsmith",
                          nick: "John Smith",
                          avatar: "http://info.thoughtworks.com/rs/thoughtworks2/images/glyph_badge.png",
                          profile: "http://img2.findthebest.com/sites/default/files/688/media/images/Mingle_159902_i0.png")
    )
    .environment(\.imageLoader, MockImageLoader())
}
