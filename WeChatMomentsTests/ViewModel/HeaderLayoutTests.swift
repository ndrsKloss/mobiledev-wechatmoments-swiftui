//
//  HeaderLayoutTests.swift
//  WeChatMomentsTests
//
//  The header's geometry as values, asserted with no view instantiated (NFR-TEST-005/006).
//
//  These are deliberately thin — the type is a handful of constants and two derivations, and no
//  amount of framing makes `avatarOverhang` a rich algorithm. What they are worth is the two
//  invariants underneath: that the view reserves exactly the space the avatar hangs into, and that
//  the header's total height is still the 398 the pagination reset quietly depends on (nfr §2.11).
//  Both used to be unwritten arithmetic in a view — `370`, and a bare `+ 28` — that nothing could
//  catch drifting apart.
//

@testable import WeChatMoments
import XCTest

final class HeaderLayoutTests: XCTestCase {

    // MARK: - The overhang

    /// The avatar straddles the banner's bottom edge: 50pt of it above, the rest below.
    func test_avatar_overhang_is_the_part_below_the_banner() {
        XCTAssertEqual(
            HeaderLayout.avatarOverhang,
            HeaderLayout.avatarSize - HeaderLayout.avatarTopAboveBannerBottom
        )
        XCTAssertEqual(HeaderLayout.avatarOverhang, 25)
    }

    /// Totality, in the `ImageGridLayout` sense: an avatar that does not reach past its own inset
    /// hangs below the banner by nothing, never by a negative amount — which would make
    /// `totalHeight` shorter than the banner it contains.
    func test_overhang_never_goes_negative() {
        XCTAssertGreaterThanOrEqual(HeaderLayout.avatarOverhang, 0)
        XCTAssertEqual(max(0, HeaderLayout.avatarSize - HeaderLayout.avatarSize * 2), 0)
    }

    // MARK: - The height the view must claim

    /// `.overlay` does not enlarge its base, so the avatar draws outside the banner's bounds. The
    /// header has to claim that space itself; if it claims less, a `List` row clips the avatar.
    func test_total_height_reserves_the_overhang_and_the_gap() {
        XCTAssertEqual(
            HeaderLayout.totalHeight,
            HeaderLayout.bannerHeight + HeaderLayout.avatarOverhang + HeaderLayout.bottomGap
        )
        XCTAssertGreaterThanOrEqual(HeaderLayout.bottomGap, 0)
        XCTAssertGreaterThan(HeaderLayout.totalHeight, HeaderLayout.bannerHeight)
    }

    /// A regression fence rather than a tautology.
    ///
    /// `nfr §2.11`: a refresh mints new `Tweet` ids, so every row is rebuilt and every `.onAppear`
    /// fires again. The only reason the window does not immediately grow 5 → 10 → 15 with no
    /// gesture is that the fifth row sits below the fold on first paint — and this number is most
    /// of the fold. Shrinking the header is therefore a `FR-PAGE-004` change, and this test is
    /// where that shows up before a device does.
    func test_total_height_matches_the_fold_the_paging_reset_depends_on() {
        XCTAssertEqual(HeaderLayout.bannerHeight, 370)
        XCTAssertEqual(HeaderLayout.totalHeight, 398)
    }

    // MARK: - What the trailing edge is made of

    /// The nick's right edge sits this far in from the header's trailing edge, at every width.
    ///
    /// It is the one number that had to survive removing the hard-coded 200pt label: the old view
    /// placed the pair at `width - 305` where 305 was `200 + 75 + 30`, putting the nick's right
    /// edge at `width - 105`. The label width is gone and the nick now takes the room the device
    /// offers, so if these three intrinsics still sum to 105 a short nick has not moved.
    func test_the_nick_still_ends_105_from_the_trailing_edge() {
        let fromTrailingEdge = HeaderLayout.trailingMargin
            + HeaderLayout.avatarSize
            + HeaderLayout.nickSpacing

        XCTAssertEqual(fromTrailingEdge, 105)
    }
}
