//
//  EnvironmentValues+ImageLoader.swift
//  WeChatMoments
//
//  The injection point for the image seam (NFR-TEST-001). Environment rather than a constructor
//  argument because RemoteImage sits several levels below the composition root and appears in many
//  places: a defaulted `init(loader: ImageLoading = ImageLoader())` would build a *new* loader per
//  view and silently destroy the shared cache. A singleton is ruled out by arch-spec §6 — "a
//  singleton is acceptable only for genuinely process-wide, stateless utilities, which a cache is
//  not."
//

import SwiftUI

private struct ImageLoaderKey: EnvironmentKey {
    /// Only reached by a view nobody injected into — previews, mainly. WeChatMomentsApp supplies
    /// the real one so the whole screen shares a cache.
    static let defaultValue: any ImageLoading = ImageLoader()
}

extension EnvironmentValues {
    var imageLoader: any ImageLoading {
        get { self[ImageLoaderKey.self] }
        set { self[ImageLoaderKey.self] = newValue }
    }
}
