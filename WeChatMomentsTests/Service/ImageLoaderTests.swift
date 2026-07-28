//
//  ImageLoaderTests.swift
//  WeChatMomentsTests
//
//  Offline, against StubURLProtocol (NFR-TEST-002). Two of these are named directly in
//  nfr §1.8 as the acceptance tests for the image pipeline: a cache hit served without a second
//  fetch, and a failure path that still calls back. The old ImageHelper failed both — it had no
//  cache at all, and its callback fired only inside the success branch.
//

@testable import WeChatMoments
import UIKit
import XCTest

final class ImageLoaderTests: XCTestCase {

    private let url = URL(string: "https://example.invalid/avatar.png")!
    private let avatarSize = CGSize(width: 40, height: 40)

    private var loader: ImageLoader!

    override func setUp() {
        super.setUp()
        loader = ImageLoader(urlSession: StubURLProtocol.makeSession())
    }

    override func tearDown() {
        StubURLProtocol.reset()
        loader = nil
        super.tearDown()
    }

    // MARK: - NFR-PERF-003 — cache

    func test_a_second_request_for_the_same_url_is_served_without_a_second_fetch() {
        StubURLProtocol.respond(status: 200, body: makePNG(side: 200), url: url)

        let first = load()
        let second = load()

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertEqual(StubURLProtocol.requestCount, 1)
    }

    /// A cache hit answers in the same runloop turn and hands back no token — hopping to the next
    /// turn for an image already in memory would flash the placeholder on every scroll-back.
    func test_a_cache_hit_calls_back_synchronously_and_returns_no_token() {
        StubURLProtocol.respond(status: 200, body: makePNG(side: 200), url: url)
        _ = load()

        var image: UIImage?
        let token = loader.loadImage(
            from: url.absoluteString,
            targetSize: avatarSize,
            displayScale: 1
        ) { image = $0 }

        XCTAssertNotNil(image, "the cache must answer before loadImage returns")
        XCTAssertNil(token)
    }

    /// The same URL at two display sizes is two bitmaps, not one — the cache key includes the
    /// pixel size, so the smaller entry must not be served where the larger was asked for.
    func test_a_different_target_size_is_a_different_cache_entry() {
        StubURLProtocol.respond(status: 200, body: makePNG(side: 200), url: url)

        _ = load(targetSize: avatarSize)
        _ = load(targetSize: CGSize(width: 120, height: 120))

        XCTAssertEqual(StubURLProtocol.requestCount, 2)
    }

    // MARK: - NFR-PERF-005 — a result on every path

    func test_a_transport_failure_still_calls_back() {
        StubURLProtocol.fail(with: URLError(.cannotConnectToHost))

        XCTAssertNil(load())
    }

    /// An error page is not an image. Without the status check the 404 body would reach ImageIO,
    /// which is the image-side twin of the defect commit 02 fixed for JSON (NFR-DATA-003).
    func test_a_404_calls_back_with_nil_rather_than_an_image_built_from_an_error_page() {
        StubURLProtocol.respond(status: 404, body: Data(#"{"error":"not found"}"#.utf8), url: url)

        XCTAssertNil(load())
        XCTAssertEqual(StubURLProtocol.requestCount, 1)
    }

    func test_a_2xx_body_that_is_not_an_image_calls_back_with_nil() {
        StubURLProtocol.respond(status: 200, body: Data("this is not a png".utf8), url: url)

        XCTAssertNil(load())
    }

    func test_an_absent_url_calls_back_and_issues_no_request() {
        var results: [UIImage?] = []

        let fromNil = loader.loadImage(from: nil, targetSize: avatarSize, displayScale: 1) { results.append($0) }
        let fromEmpty = loader.loadImage(from: "", targetSize: avatarSize, displayScale: 1) { results.append($0) }

        XCTAssertEqual(results.count, 2, "both must call back rather than silently doing nothing")
        XCTAssertNil(results.first ?? nil)
        XCTAssertNil(results.last ?? nil)
        XCTAssertNil(fromNil)
        XCTAssertNil(fromEmpty)
        XCTAssertEqual(StubURLProtocol.requestCount, 0)
    }

    // MARK: - NFR-PERF-006 — coalescing and cancellation

    func test_two_concurrent_requests_for_one_url_share_a_single_fetch() {
        StubURLProtocol.respond(status: 200, body: makePNG(side: 200), url: url)
        // Hold the response open so the second request genuinely overlaps the first; otherwise
        // the cache would satisfy this assertion and the coalescing path would go untested.
        StubURLProtocol.responseDelay = 0.3

        let first = expectation(description: "first")
        let second = expectation(description: "second")
        var images: [UIImage?] = []

        loader.loadImage(from: url.absoluteString, targetSize: avatarSize, displayScale: 1) {
            images.append($0)
            first.fulfill()
        }
        loader.loadImage(from: url.absoluteString, targetSize: avatarSize, displayScale: 1) {
            images.append($0)
            second.fulfill()
        }

        wait(for: [first, second], timeout: 3)

        XCTAssertEqual(images.compactMap { $0 }.count, 2)
        XCTAssertEqual(StubURLProtocol.requestCount, 1)
    }

    func test_a_cancelled_request_does_not_call_back() throws {
        StubURLProtocol.respond(status: 200, body: makePNG(side: 200), url: url)
        StubURLProtocol.responseDelay = 0.2

        let token = loader.loadImage(from: url.absoluteString, targetSize: avatarSize, displayScale: 1) { _ in
            XCTFail("a cancelled request must not deliver a result")
        }
        loader.cancel(try XCTUnwrap(token))

        // Long enough for the held response to have landed had it not been cancelled.
        let settled = expectation(description: "settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { settled.fulfill() }
        wait(for: [settled], timeout: 3)
    }

    /// The reason cancellation is refcounted rather than a bare `task.cancel()`: one row scrolling
    /// away must not cancel the download the rows still on screen are waiting for.
    func test_cancelling_one_of_two_sharers_still_delivers_to_the_other() throws {
        StubURLProtocol.respond(status: 200, body: makePNG(side: 200), url: url)
        StubURLProtocol.responseDelay = 0.3

        let survivor = expectation(description: "survivor")
        var delivered: UIImage?

        let leaving = loader.loadImage(from: url.absoluteString, targetSize: avatarSize, displayScale: 1) { _ in
            XCTFail("the cancelled sharer must not deliver")
        }
        loader.loadImage(from: url.absoluteString, targetSize: avatarSize, displayScale: 1) {
            delivered = $0
            survivor.fulfill()
        }
        loader.cancel(try XCTUnwrap(leaving))

        wait(for: [survivor], timeout: 3)

        XCTAssertNotNil(delivered)
        XCTAssertEqual(StubURLProtocol.requestCount, 1)
    }

    // MARK: - NFR-PERF-007 — downsampling

    func test_a_large_image_is_downsampled_to_its_display_size() throws {
        StubURLProtocol.respond(status: 200, body: makePNG(side: 1000), url: url)

        let image = try XCTUnwrap(load(targetSize: avatarSize, displayScale: 1))

        XCTAssertLessThanOrEqual(image.size.width, avatarSize.width)
        XCTAssertLessThanOrEqual(image.size.height, avatarSize.height)
    }

    func test_display_scale_is_honoured_so_a_retina_cell_is_not_served_a_blurred_image() throws {
        StubURLProtocol.respond(status: 200, body: makePNG(side: 1000), url: url)

        let image = try XCTUnwrap(load(targetSize: avatarSize, displayScale: 3))

        // 40pt at 3x is 120px, and UIImage(cgImage:) reports pixels as points at scale 1.
        XCTAssertEqual(image.size.width, 120, accuracy: 1)
    }

    func test_a_zero_target_size_skips_downsampling() throws {
        StubURLProtocol.respond(status: 200, body: makePNG(side: 300), url: url)

        let image = try XCTUnwrap(load(targetSize: .zero))

        XCTAssertEqual(image.size.width, 300, accuracy: 1)
    }

    // MARK: - Helpers

    /// Issues one request and blocks until it calls back. A test that hangs here is a test that
    /// found the `ImageHelper` defect: a path that never completes.
    private func load(targetSize: CGSize? = nil, displayScale: CGFloat = 1) -> UIImage? {
        let delivered = expectation(description: "image delivered")
        var image: UIImage?

        loader.loadImage(
            from: url.absoluteString,
            targetSize: targetSize ?? avatarSize,
            displayScale: displayScale
        ) {
            image = $0
            delivered.fulfill()
        }

        wait(for: [delivered], timeout: 3)
        return image
    }

    /// A real PNG, generated rather than bundled — nothing here needs a fixture on disk or a
    /// running mountebank (NFR-TEST-002).
    private func makePNG(side: CGFloat) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.pngData { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }
}
