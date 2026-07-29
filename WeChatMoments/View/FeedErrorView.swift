//
//  FeedErrorView.swift
//  WeChatMoments
//
//  The visual treatment FAD-DATA-c was open on, resolved 2026-07-29 in favour of a full-screen
//  message (nfr §2.13).
//

import SwiftUI

/// FR-FEED-004: what stands where the feed would be when the feed request fails outright — a
/// message, rather than an empty list or an indicator that spins forever (`fn-spec §7`, last
/// bullet).
///
/// It draws below the header rather than over the whole screen: the two requests are independent
/// (`FR-FEED-005`), so a profile that loaded should still be visible when the feed did not.
///
/// There is no Retry button by design. `nfr §2.9` carries the assumption that a failed request
/// stays failed until the user refreshes, and pull-to-refresh is `FR-PAGE-004` — commit 08.
struct FeedErrorView: View {
    let error: NetworkError

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("Couldn't load the feed")
                .font(.headline)

            // NFR-DATA-005 paying off: the error arrives as a typed value, so the reason is the
            // real one. `NetworkError` already conforms to `LocalizedError` (FAD-DATA-b), which
            // is why this view maps no cases of its own.
            if let reason = error.errorDescription {
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)   // NFR-LAYOUT-001: no assumed width
        .padding(.horizontal, 32)
        .padding(.vertical, 64)
    }
}

#Preview("Unreachable") {
    FeedErrorView(error: .transport(URLError(.cannotConnectToHost)))
}

#Preview("404") {
    FeedErrorView(error: .httpStatus(404))
}

#Preview("Undecodable") {
    FeedErrorView(error: .decoding(URLError(.cannotDecodeRawData)))
}
