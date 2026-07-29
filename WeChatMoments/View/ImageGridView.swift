//
//  ImageGridView.swift
//  WeChatMoments
//
//  The 0-to-9 image grid of fn-spec §5 (FR-TWEET-004/005/009/010/011).
//
//  It replaces `TweetView.addImagesToView(_from:)`, which drew a fixed 0..<5 range and ended in
//  `.padding() as? AnyView` — a cast that always evaluated to nil, so it had never rendered an
//  image at all. fn-spec §4.4 asked for a rewrite rather than a patch; this is it.
//

import SwiftUI

/// Draws a tweet's images, and owns the "no images, no grid" rule itself — the same shape as
/// `CommentBlockView`, so `TweetView`'s body stays a list of unconditional children.
///
/// Every layout sits inside one three-column track (`ImageGridLayout.trackColumns`). That is the
/// whole trick: no code here computes a width, so the cells are a third of whatever space the
/// device and orientation actually offer (FR-TWEET-010, NFR-LAYOUT-001/003).
struct ImageGridView: View {
    var images: [Img]?

    var body: some View {
        if let images, !images.isEmpty,
           let plan = ImageGridLayout.plan(forImageCount: images.count) {
            let rows = ImageGridLayout.rows(images, perRow: plan.imagesPerRow)

            Grid(
                alignment: .topLeading,
                horizontalSpacing: Constants.TWEET_IMAGE_SEPARATOR_SPACE,
                verticalSpacing: Constants.TWEET_IMAGE_SEPARATOR_SPACE
            ) {
                // `Img` carries no identity and this is a static, non-lazy stack scoped to one
                // tweet, so positional identity is stable — the same reasoning as the comment
                // rows. NFR-DATA-007 governs the feed `List`, which keys on `Tweet.id`.
                ForEach(rows.indices, id: \.self) { row in
                    GridRow {
                        ForEach(rows[row].indices, id: \.self) { column in
                            cell(rows[row][column], span: plan.columnSpan)
                        }

                        // A short row would otherwise let the track collapse to fewer columns and
                        // the surviving cells would grow to fill the width. These hold the
                        // columns open; they are not image cells, so FR-TWEET-004's "exactly as
                        // many cells as images" is untouched.
                        ForEach(0..<emptyColumns(after: rows[row].count, plan: plan), id: \.self) { _ in
                            Color.clear.aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
        }
    }

    /// FR-TWEET-009: square, uniform within the tweet, aspect-fill, clipped — no distortion.
    ///
    /// `RemoteImage` applies `.resizable()` and its content mode but never a `.frame`
    /// (arch-spec §8.4), so the square comes from here: a flexible box with a 1:1 ratio takes the
    /// column's width and answers with the matching height.
    private func cell(_ image: Img, span: Int) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                // NFR-DATA-004: a missing or failed image is the placeholder asset, not a crash.
                RemoteImage(
                    urlString: image.url,
                    targetSize: downsampleHint(span: span),
                    contentMode: .fill
                )
            }
            .clipped()
            .gridCellColumns(span)
    }

    private func emptyColumns(after imagesInRow: Int, plan: ImageGridLayout.Plan) -> Int {
        max(0, ImageGridLayout.trackColumns - imagesInRow * plan.columnSpan)
    }

    /// NFR-PERF-007: the size the loader downsamples to. It is a *resolution hint*, not a layout
    /// input — nothing here is framed to it — so `Constants.IMAGE_SIZE` is used in the sense
    /// arch-spec §9 allows, as an intrinsic value, and never to derive a container width.
    ///
    /// The cost of the hint being a constant: on a device wider than the one the 82pt figure was
    /// read from, the real cell is larger and the thumbnail is scaled up a little.
    private func downsampleHint(span: Int) -> CGSize {
        let side = Constants.IMAGE_SIZE.width * CGFloat(span)
            + Constants.TWEET_IMAGE_SEPARATOR_SPACE * CGFloat(span - 1)
        return CGSize(width: side, height: side)
    }
}

// Each row of fn-spec §5. The 4- and 9-image cases sit below the fold in the running app, so
// these previews are how they get looked at.
#Preview("§5 — every image count") {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(0...9, id: \.self) { count in
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ImageGridView(images: .preview(count))
            }
        }
        .padding()
    }
    .environment(\.imageLoader, MockImageLoader())
}

#Preview("Absent and empty render nothing") {
    VStack(alignment: .leading) {
        Text("nothing may appear below this line")
            .font(.footnote)
        ImageGridView(images: nil)
        ImageGridView(images: [])
    }
    .padding()
}

#if DEBUG
private extension Array where Element == Img {
    static func preview(_ count: Int) -> [Img] {
        (0..<count).map { Img(url: "https://example.invalid/\($0).jpeg") }
    }
}
#endif
