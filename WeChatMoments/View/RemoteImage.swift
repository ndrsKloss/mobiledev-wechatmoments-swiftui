//
//  RemoteImage.swift
//  WeChatMoments
//
//  The fix for arch-spec §8.4 — "Views MUST NOT own image-loading state in a local variable."
//  TweetView.avatar(_from:) and fetchImage(_from:) started an asynchronous load and then returned
//  a local `var` the callback had not written yet, so they could only ever return the placeholder.
//  The state has to be owned by a view that can re-render when it changes.
//

import SwiftUI

struct RemoteImage: View {
    let urlString: String?
    let targetSize: CGSize
    var contentMode: ContentMode = .fill

    @Environment(\.imageLoader) private var imageLoader
    /// The scale of the display this view is actually on — SwiftUI's own answer, and the reason
    /// the loader never has to reach for `UIScreen` from a background queue.
    @Environment(\.displayScale) private var displayScale

    @State private var image: UIImage?
    /// Held so the request can be cancelled when the row leaves the screen (`NFR-PERF-006`).
    @State private var token: ImageRequestToken?

    var body: some View {
        // NFR-DATA-004: a missing or failed image is the placeholder asset, never a force-unwrap.
        (image.map { Image(uiImage: $0) } ?? Image(Constants.DEFAULT_EMPTY_IMAGE))
            .resizable()
            .aspectRatio(contentMode: contentMode)
            .onAppear(perform: load)
            .onDisappear(perform: cancel)
            // A row in a lazy container is reused for a different tweet, and the @State above
            // survives that reuse. Without this the cell would keep showing the previous URL's
            // image — the view-identity trap arch-spec §12 exists to point at.
            .onChange(of: urlString) { _, _ in
                cancel()
                image = nil
                load()
            }
    }

    private func load() {
        // .onAppear fires again every time the row scrolls back into view; without this guard
        // that would be a fresh request each time, which the cache would serve but the
        // bookkeeping would not thank us for.
        guard image == nil, token == nil else { return }

        token = imageLoader.loadImage(
            from: urlString,
            targetSize: targetSize,
            displayScale: displayScale
        ) { loaded in
            image = loaded
            token = nil
        }
    }

    private func cancel() {
        if let token {
            imageLoader.cancel(token)
        }
        token = nil
    }
}

#Preview {
    RemoteImage(
        urlString: "https://example.invalid/avatar.png",
        targetSize: Constants.SENDER_AVATAR_SIZE
    )
    .frame(width: 120, height: 120)
    .environment(\.imageLoader, MockImageLoader())
}
