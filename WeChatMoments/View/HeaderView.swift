//
//  HeaderView.swift
//  WeChatMoments
//
//  Created by Tushar Sharma on 09/03/24.
//

import SwiftUI

struct HeaderView: View {
    /// The only metric that is still local: it is used once, by one view, and `arch-spec §9` lets
    /// single-view values stay local. It stays a point size because Dynamic Type is out of scope
    /// (`NFR-LAYOUT-005`, `FAD-LAYOUT-b`). Everything geometric lives in `HeaderLayout`.
    private let nickNameFontSize: CGFloat = 16

    var user: User?

    /// Derived from `user`, so it is not @State. Storing it in @State — as this view used to —
    /// makes the view the owner of a value it does not own, and the copy goes stale the moment
    /// `user` arrives a second time.
    private var nickname: String { user?.nick ?? "" }

    var body: some View {
        banner
            .frame(height: HeaderLayout.bannerHeight)
            // Before `.overlay`, deliberately: after it, this would clip the very overhang the
            // bottom padding exists to reserve.
            .clipped()
            // NFR-LAYOUT-001/002: the nick and avatar are *aligned* to the banner's bottom-trailing
            // corner rather than pushed there by `.offset(x: proxy.size.width - 305, y: 370 - 50)`.
            // The old arithmetic subtracted a hard-coded 200pt label width from the device width,
            // and re-derived the vertical position from the banner height every time it was read.
            .overlay(alignment: .bottomTrailing) { nickAndAvatar }
            // The overlay draws outside the banner, and `.overlay` never enlarges its base — so
            // the space the avatar hangs into has to be claimed here or the List row clips it.
            .padding(.bottom, HeaderLayout.avatarOverhang + HeaderLayout.bottomGap)
    }

    private var banner: some View {
        GeometryReader { proxy in
            // The banner is downsampled to the space it actually occupies, not to
            // Constants.SENDER_PROFILE_SIZE (75×75) as the old loader was asked for — that
            // would have thumbnailed a full-bleed cover image to avatar size.
            RemoteImage(
                urlString: user?.profile,
                targetSize: CGSize(width: proxy.size.width, height: HeaderLayout.bannerHeight)
            )
            // Not redundant with the outer `.frame`. RemoteImage fills, so it answers with a size
            // *larger* than the proposal on one axis; this frame's default .center alignment is
            // what makes the excess crop from both edges. A GeometryReader would instead pin the
            // oversized image to .topLeading and the banner would crop top-left.
            .frame(width: proxy.size.width, height: HeaderLayout.bannerHeight)
        }
    }

    private var nickAndAvatar: some View {
        HStack(spacing: HeaderLayout.nickSpacing) {
            Text(nickname)
                .font(.system(size: nickNameFontSize, weight: .bold))
                .foregroundStyle(.white)
                // FR-HEADER-002, NFR-LAYOUT-004: the nick truncates by design — but at the width
                // the device actually offers, not at a hard-coded 200pt. A short nick lands in
                // exactly the same place; a long one now uses the room it has.
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.bottom, 15)
                .frame(maxWidth: .infinity, alignment: .trailing)

            avatar
        }
        .padding(.trailing, HeaderLayout.trailingMargin)
        // The overhang, stated once. `.offset(y:)` and a negative bottom padding both draw the
        // same pixels, but each says it twice — this moves the alignment target itself.
        .alignmentGuide(.bottom) { $0[.bottom] - HeaderLayout.avatarOverhang }
    }

    private var avatar: some View {
        RemoteImage(
            urlString: user?.avatar,
            targetSize: CGSize(width: HeaderLayout.avatarSize, height: HeaderLayout.avatarSize)
        )
        .frame(width: HeaderLayout.avatarSize, height: HeaderLayout.avatarSize)
        .clipShape(.rect(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(.white, lineWidth: 2)
        }
    }
}

#if DEBUG
private let previewUser = User(
    username: "jsmith",
    nick: "Huan Huan",
    avatar: "http://info.thoughtworks.com/rs/thoughtworks2/images/glyph_badge.png",
    profile: "http://img2.findthebest.com/sites/default/files/688/media/images/Mingle_159902_i0.png"
)
#endif

#Preview("Huan Huan") {
    HeaderView(user: previewUser)
        .environment(\.imageLoader, MockImageLoader())
}

// nfr §3.7 asks for previews pinned to several device sizes. The avatar's trailing edge and its
// overhang below the banner must not move between these; only the room left for the nick changes.
#Preview("Narrow and wide") {
    VStack(spacing: 0) {
        ForEach([320.0, 440.0], id: \.self) { width in
            HeaderView(user: previewUser)
                .frame(width: width)
        }
    }
    .environment(\.imageLoader, MockImageLoader())
}

// The case the old fixed-200 label truncated early, and the reason NFR-LAYOUT-004 says the header
// nick truncates *by design*: past the available width it still does, in the middle.
#Preview("Long nick truncates in the middle") {
    VStack(spacing: 0) {
        ForEach([320.0, 440.0], id: \.self) { width in
            HeaderView(user: User(username: "jsmith",
                                  nick: "Huan Huan Huan Huan Huan Huan Huan Huan",
                                  avatar: previewUser.avatar,
                                  profile: previewUser.profile))
                .frame(width: width)
        }
    }
    .environment(\.imageLoader, MockImageLoader())
}

// A missing user is the state the header is in for the first frame of every launch (FR-FEED-005).
#Preview("No user yet") {
    HeaderView(user: nil)
        .environment(\.imageLoader, MockImageLoader())
}
