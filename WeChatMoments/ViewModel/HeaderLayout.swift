//
//  HeaderLayout.swift
//  WeChatMoments
//
//  The profile header's geometry, as values rather than as arithmetic scattered through the view
//  (NFR-TEST-006). `HeaderView` used to derive the avatar's position by subtracting hard-coded
//  numbers from `GeometryProxy.size.width` inside two private instance methods, which made the one
//  rule that actually matters here — how far the avatar hangs below the banner, and that the view
//  must reserve exactly that much space — impossible to assert without rendering a view.
//
//  These are intrinsic sizes in the sense arch-spec §9 allows: they describe the header itself, not
//  the device it is drawn on. Nothing here is, or may become, a container width (NFR-LAYOUT-001).
//

import Foundation

enum HeaderLayout {

    /// The banner's height. Fixed by decision, not by accident: `nfr §2.11` records that
    /// `FR-PAGE-004`'s "refresh resets to 5 and stays 5" survives only because the fifth row sits
    /// below the fold on first paint, and this constant is most of the reason it does. Changing it
    /// is a paging change as much as a layout one — see `totalHeight`.
    static let bannerHeight: CGFloat = 370

    /// Intrinsic, like every other avatar in the app.
    static let avatarSize: CGFloat = 75

    /// The avatar's top edge sits this far *above* the banner's bottom edge, so it straddles it.
    static let avatarTopAboveBannerBottom: CGFloat = 50

    /// Between the nick and the avatar.
    static let nickSpacing: CGFloat = 20

    /// Between the avatar and the header's trailing edge.
    static let trailingMargin: CGFloat = 10

    /// Breathing room below the avatar, before the first tweet.
    static let bottomGap: CGFloat = 3

    /// How much of the avatar hangs below the banner.
    ///
    /// `max(0, …)` keeps this total: an avatar smaller than its own inset does not straddle the
    /// edge at all, and a negative overhang would make `totalHeight` shorter than the banner.
    static let avatarOverhang = max(0, avatarSize - avatarTopAboveBannerBottom)

    /// The height the header claims, and the invariant the view must honour.
    ///
    /// The overhang is drawn *outside* the banner, so if the view does not reserve it the avatar is
    /// clipped at the `List` row boundary. Deriving both numbers from the same place is what stops
    /// the two drifting apart — they were `370` and a bare `+ 28` in two different expressions.
    static let totalHeight = bannerHeight + avatarOverhang + bottomGap
}
