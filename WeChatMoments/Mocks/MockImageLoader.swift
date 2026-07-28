//
//  MockImageLoader.swift
//  WeChatMoments
//

#if DEBUG
import UIKit

/// Test double for the image seam (`arch-spec §10.3`, `NFR-TEST-001/007`). Lives in the app target
/// so previews and tests share it; it contains no production logic — no cache, no coalescing, no
/// network.
final class MockImageLoader: ImageLoading {

    struct Request: Equatable {
        let urlString: String?
        let targetSize: CGSize
        let displayScale: CGFloat
    }

    /// Every call, in order — this is how a test asserts a view asked for the URL it claims to.
    private(set) var requests: [Request] = []

    /// Every token handed to `cancel(_:)`, in order.
    private(set) var cancelledTokens: [ImageRequestToken] = []

    /// What every call returns. `nil` models the failure path, which is the one the old
    /// `ImageHelper` never reached (`NFR-PERF-005`).
    var result: UIImage?

    /// When false, completions are held until `deliverPending()` — which is how a test observes
    /// the placeholder state a real network delay would produce.
    var deliversImmediately = true

    private var pending: [(UIImage?) -> Void] = []

    var callCount: Int { requests.count }

    init(result: UIImage? = nil) {
        self.result = result
    }

    @discardableResult
    func loadImage(
        from urlString: String?,
        targetSize: CGSize,
        displayScale: CGFloat,
        completion: @escaping (UIImage?) -> Void
    ) -> ImageRequestToken? {
        requests.append(Request(urlString: urlString, targetSize: targetSize, displayScale: displayScale))

        guard deliversImmediately else {
            pending.append(completion)
            return ImageRequestToken(key: urlString ?? "")
        }

        completion(result)
        return nil
    }

    func cancel(_ token: ImageRequestToken) {
        cancelledTokens.append(token)
    }

    func deliverPending() {
        let completions = pending
        pending.removeAll()
        completions.forEach { $0(result) }
    }
}
#endif
