//
//  ImageGridLayout.swift
//  WeChatMoments
//
//  fn-spec §5 expressed as a pure function of the image count (NFR-TEST-006), so the one part of
//  the grid that is a *rule* rather than a drawing can be asserted without a view.
//

import Foundation

enum ImageGridLayout {

    /// Every layout in fn-spec §5 is drawn inside the same three-column track; only what goes
    /// into that track changes. Keeping the track fixed is what lets a cell be "one third of the
    /// available width" without any code ever computing a width (FR-TWEET-010, NFR-LAYOUT-003).
    static let trackColumns = 3

    /// How one tweet's images fill the track.
    struct Plan: Equatable {
        /// Images per row — 1, 2 or 3. Not the same as the columns they occupy.
        let imagesPerRow: Int
        /// Track columns each image spans. 2 only for the single-image case, which fn-spec §5
        /// asks to render "larger than a grid cell".
        let columnSpan: Int
    }

    /// fn-spec §5, as a total function. `nil` means no grid is rendered at all — FR-TWEET-004's
    /// zero-image case, which is *nothing*, not an empty container.
    ///
    /// Counts above 9 break the data contract rather than this function: they fall into the plain
    /// three-column case instead of trapping.
    static func plan(forImageCount count: Int) -> Plan? {
        switch count {
        case ..<1:
            return nil
        case 1:
            // §5 row 1 [A] — see fn-spec §8 Q3 for what "larger" was taken to mean.
            return Plan(imagesPerRow: 1, columnSpan: 2)
        case 4:
            // §5 row 3 [A] — the classic WeChat 2×2. Two images per row inside a three-column
            // track, so the cells stay exactly the size they are in every other layout.
            return Plan(imagesPerRow: 2, columnSpan: 1)
        default:
            // 2–3 (one row, left-aligned, not stretched), 5–6 (partial last row) and 7–9.
            return Plan(imagesPerRow: 3, columnSpan: 1)
        }
    }

    /// Chunks images into rows, order preserved, left to right then down.
    ///
    /// A short final row keeps only the images it has — FR-TWEET-004 wants exactly as many cells
    /// as there are images, with no placeholder padding. Holding the *columns* open is a drawing
    /// concern and belongs to the view.
    static func rows<T>(_ images: [T], perRow: Int) -> [[T]] {
        guard perRow > 0 else { return [] }

        return stride(from: 0, to: images.count, by: perRow).map { start in
            Array(images[start..<min(start + perRow, images.count)])
        }
    }
}
