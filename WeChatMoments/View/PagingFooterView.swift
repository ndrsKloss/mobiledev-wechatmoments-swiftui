//
//  PagingFooterView.swift
//  WeChatMoments
//

import SwiftUI

/// The "more below" row under the last displayed tweet (`FR-PAGE-007`).
///
/// It looks like an infinite-scroll spinner and is not one. Appending a page is synchronous — the
/// whole feed is already in memory (`NFR-PERF-008`) — so there is no in-flight period for a real
/// loading indicator to report, and `fn-spec §8 Q4` declined one on exactly that ground. What this
/// reports instead is that the window has feed behind it: `MomentsViewModel.hasMorePages`, derived
/// from the same two numbers the window is.
///
/// The behaviour that makes the borrowed vocabulary honest is when it *stops*. The append trigger
/// sits on the last tweet row, which becomes visible fractionally before this one does, so by the
/// time this row is on screen the next page has already landed and pushed it down. On the final
/// page `hasMorePages` is false and the row is gone. The user sees a spinner while there is more
/// to come and never sees one spinning at the end of the feed.
struct PagingFooterView: View {
    var body: some View {
        HStack {
            Spacer()
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .padding(.vertical, Constants.PAGING_FOOTER_PADDING)
            Spacer()
        }
        // NFR-LAYOUT-001: sized by its content and the width the row offers, no fixed metrics.
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    List {
        Text("last tweet")
        PagingFooterView()
    }
    .listStyle(PlainListStyle())
}
