//
//  WeChatMomentsApp.swift
//  WeChatMoments
//
//  Created by Tushar Sharma on 22/02/24.
//

import SwiftUI

@main
struct WeChatMomentsApp: App {
    /// The composition root for the image seam. One loader for the whole screen, so header,
    /// avatars and grid share a cache (NFR-PERF-003) — a per-view default argument would not.
    /// This is a step toward FAD-ARCH-d, not a resolution of it.
    @State private var imageLoader = ImageLoader()

    var body: some Scene {
        WindowGroup {
            MomentView()
                .environment(\.imageLoader, imageLoader)
        }
    }
}
