//
//  ImageLoader.swift
//  WeChatMoments
//
//  Replaces Utils/ImageHelper.swift, which arch-spec §8 records as unpatchable: a synchronous
//  overload that returned nil unconditionally, an asynchronous one that blocked on
//  Data(contentsOf:) and called back only on success, no cache, and a `forSize:` it ignored.
//

import ImageIO
import UIKit

/// Handle for an in-flight request. Opaque on purpose — the caller's only verb is `cancel(_:)`,
/// and a value type means a view can hold one in `@State` without an ownership question.
struct ImageRequestToken: Hashable {
    fileprivate let id: UUID
    fileprivate let key: String

    /// Only `ImageLoader` mints these in production; the initializer is internal so a test double
    /// can hand one back too.
    init(id: UUID = UUID(), key: String) {
        self.id = id
        self.key = key
    }
}

/// The image seam (`arch-spec §8.1`). Injected as a protocol so the concurrency mechanism behind
/// it stays an implementation detail — see `FAD-PERF-a` in `nfr §1.10`.
protocol ImageLoading: AnyObject {

    /// Delivers exactly one result on the main thread, on **every** path — absent or unparseable
    /// URL, transport error, non-2xx status, undecodable bytes (`NFR-PERF-005`). `nil` is a
    /// placeholder, not an error state: a missing avatar must not blank the feed.
    ///
    /// Returns a token to cancel with, or `nil` when there is nothing to cancel because the
    /// completion has already run — a cache hit or an unusable URL both answer synchronously.
    ///
    /// `targetSize` is in points; `displayScale` converts it to pixels. Scale belongs to the
    /// display the image is bound for, not to the loader, so it arrives with the request.
    /// `targetSize == .zero` means "do not downsample".
    ///
    /// **Must be called from the main thread**, which is where a SwiftUI view body and its
    /// lifecycle callbacks already are.
    @discardableResult
    func loadImage(
        from urlString: String?,
        targetSize: CGSize,
        displayScale: CGFloat,
        completion: @escaping (UIImage?) -> Void
    ) -> ImageRequestToken?

    /// Drops this caller's interest. The underlying download is cancelled only when the last
    /// interested caller leaves (`NFR-PERF-006`). A cancelled request does not call back.
    func cancel(_ token: ImageRequestToken)
}

/// GCD-backed, as the brief asks (`README.md` → *Tech requirements*: "Utilise GCD for multi-thread
/// operation"). Three queues do three jobs: `URLSession`'s own for transport, `stateQueue` to
/// serialise access to the cache bookkeeping, and `decodeQueue` for the ImageIO work. Nothing but
/// the final completion touches the main thread.
final class ImageLoader: ImageLoading {

    /// One entry per in-flight URL+size. `subscribers` is what makes cancellation safe: a row
    /// scrolling off screen must drop its own interest without cancelling a download the rows
    /// still on screen are waiting for (`NFR-PERF-006`).
    private struct InFlight {
        let task: URLSessionDataTask
        let generation: UUID
        var subscribers: [UUID: (UIImage?) -> Void]
    }

    private let urlSession: URLSession

    /// FAD-PERF-b: memory-only, no explicit eviction. `NSCache` already evicts under memory
    /// pressure and is thread-safe. Caching decoded, downsampled `UIImage`s rather than bytes is
    /// the point — re-decoding on every scroll-back is the expensive half.
    private let cache = NSCache<NSString, UIImage>()

    /// Serial. Every read and write of `inFlight` goes through it, so the table needs no lock and
    /// no `@Synchronized` ceremony. Being serial also orders `cancel` after the `loadImage` that
    /// produced the token, even though `loadImage` returns before its own block has run.
    private let stateQueue = DispatchQueue(label: "com.gl.WeChatMoments.imageloader.state")

    /// Concurrent: decoding two images at once is the whole reason for a thread pool, and ImageIO
    /// has no shared state to protect.
    private let decodeQueue = DispatchQueue(
        label: "com.gl.WeChatMoments.imageloader.decode",
        qos: .userInitiated,
        attributes: .concurrent
    )

    private var inFlight: [String: InFlight] = [:]

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    @discardableResult
    func loadImage(
        from urlString: String?,
        targetSize: CGSize,
        displayScale: CGFloat,
        completion: @escaping (UIImage?) -> Void
    ) -> ImageRequestToken? {
        // NFR-PERF-005: the invalid-URL path answers rather than leaving the caller waiting.
        guard let urlString, !urlString.isEmpty, let url = URL(string: urlString) else {
            completion(nil)
            return nil
        }

        let pixelSize = Self.pixelSize(of: targetSize, at: displayScale)
        let key = Self.cacheKey(url: url, pixelSize: pixelSize)

        // NFR-PERF-003: cache before network, always. Answering synchronously matters — hopping to
        // the next runloop turn for an image we already hold would flash the placeholder on every
        // scroll-back, which is the exact stutter the cache exists to prevent.
        if let cached = cache.object(forKey: key as NSString) {
            completion(cached)
            return nil
        }

        let token = ImageRequestToken(id: UUID(), key: key)

        stateQueue.async { [weak self] in
            guard let self else { return }

            // NFR-PERF-006: duplicate concurrent requests for one URL share a single download.
            if var entry = self.inFlight[key] {
                entry.subscribers[token.id] = completion
                self.inFlight[key] = entry
                return
            }

            let generation = UUID()
            let task = self.urlSession.dataTask(with: url) { [weak self] data, response, _ in
                guard let self else { return }
                self.decodeQueue.async {
                    let image = Self.makeImage(data: data, response: response, pixelSize: pixelSize)
                    self.finish(key: key, generation: generation, image: image)
                }
            }

            self.inFlight[key] = InFlight(
                task: task,
                generation: generation,
                subscribers: [token.id: completion]
            )
            task.resume()
        }

        return token
    }

    func cancel(_ token: ImageRequestToken) {
        stateQueue.async { [weak self] in
            guard let self, var entry = self.inFlight[token.key] else { return }

            entry.subscribers.removeValue(forKey: token.id)
            if entry.subscribers.isEmpty {
                entry.task.cancel()
                self.inFlight[token.key] = nil
            } else {
                self.inFlight[token.key] = entry
            }
        }
    }

    // MARK: - Completion

    /// The `generation` check stops a cancelled download, finishing late, from evicting the entry
    /// a newer request for the same key has since installed and answering its subscribers with the
    /// cancelled result.
    private func finish(key: String, generation: UUID, image: UIImage?) {
        stateQueue.async { [weak self] in
            guard let self else { return }

            if let image {
                self.cache.setObject(image, forKey: key as NSString)
            }

            guard self.inFlight[key]?.generation == generation,
                  let entry = self.inFlight.removeValue(forKey: key)
            else { return }

            let subscribers = Array(entry.subscribers.values)
            // NFR-PERF-004: UI state changes are delivered on the main thread.
            DispatchQueue.main.async {
                subscribers.forEach { $0(image) }
            }
        }
    }

    // MARK: - Decoding

    private static func makeImage(data: Data?, response: URLResponse?, pixelSize: CGSize) -> UIImage? {
        // The same 2xx rule HttpService applies (NFR-DATA-003): an error page is not an image.
        guard let data,
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else { return nil }

        return downsample(data, to: pixelSize)
    }

    /// FAD-PERF-c: ImageIO thumbnails rather than a redraw. `CGImageSourceCreateThumbnailAtIndex`
    /// never decodes the full-size bitmap, which is what NFR-PERF-007's "before being held in
    /// memory" actually asks for; a `UIGraphicsImageRenderer` redraw would decode first and shrink
    /// after, saving nothing at the moment it matters.
    private static func downsample(_ data: Data, to pixelSize: CGSize) -> UIImage? {
        guard pixelSize != .zero,
              let source = CGImageSourceCreateWithData(
                  data as CFData,
                  [kCGImageSourceShouldCache: false] as CFDictionary
              )
        else {
            return UIImage(data: data)
        }

        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(pixelSize.width, pixelSize.height)
        ] as CFDictionary

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: thumbnail)
    }

    private static func pixelSize(of targetSize: CGSize, at displayScale: CGFloat) -> CGSize {
        guard targetSize != .zero, displayScale > 0 else { return .zero }
        return CGSize(width: targetSize.width * displayScale, height: targetSize.height * displayScale)
    }

    /// Pixel size is part of the key, because it is part of the identity of the cached bitmap: the
    /// same URL at avatar size and at grid size are two legitimately different images, and sharing
    /// one entry would serve whichever arrived first.
    private static func cacheKey(url: URL, pixelSize: CGSize) -> String {
        "\(url.absoluteString)|\(Int(pixelSize.width))x\(Int(pixelSize.height))"
    }
}
