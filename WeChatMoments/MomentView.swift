//
//  MomentView.swift
//  WeChatMoments
//
//  Created by Tushar Sharma on 22/02/24.
//

import SwiftUI

struct MomentView: View {
    @ObservedObject var momentsViewModel = MomentsViewModel()

    private var indicatorView:some View {
        return ProgressView()
            .progressViewStyle(CircularProgressViewStyle())
            .controlSize(.large)
    }

    private var tweets:[Tweet] {
        return momentsViewModel.tweets?.compactMap{ $0 } ?? []
    }

    private var user: User? {
        return momentsViewModel.user
    }

    var body: some View {
        List {
            Group {
                HeaderView(user: user)
                // NFR-DATA-007: Tweet carries its own stable id; \.self would collide
                // on duplicate content.
                ForEach(tweets) { tweet in
                    // One List row per tweet. The separator has to live *inside* the row: as a
                    // sibling of TweetView it became a row of its own, and a List row has a
                    // minimum height, so the hairline reserved ~44pt of empty space under every
                    // cell. The ad-hoc Divider that stood here had the same problem.
                    VStack(spacing: 0) {
                        TweetView(tweet: tweet)
                        FooterView()   // FR-TWEET-008
                    }
                }
                .listRowSeparator(.hidden)
            }
            .listRowInsets(EdgeInsets())
        }
        .listStyle(PlainListStyle())
        .overlay(content: {
            if momentsViewModel.showIndicator {
                indicatorView
            }
        })
        .onAppear {
            momentsViewModel.loadData()
        }.ignoresSafeArea()
    }
}

#Preview {
    MomentView()
}
