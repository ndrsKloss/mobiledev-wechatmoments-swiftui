//
//  HttpServiceTests.swift
//  WeChatMomentsTests
//
//  Offline. These pin NFR-DATA-003 / FR-API-005 — status validation — against a scripted
//  URLProtocol rather than a running mountebank (NFR-TEST-002). The end-to-end contract check
//  that genuinely needs the mock lives in Integration/HttpServiceIntegrationTests.swift.
//

@testable import WeChatMoments
import Combine
import XCTest

final class HttpServiceTests: XCTestCase {

    private var service: HttpService!
    private let url = URL(string: "https://example.invalid/user/jsmith")!

    override func setUp() {
        super.setUp()
        service = HttpService(urlSession: StubURLProtocol.makeSession())
    }

    override func tearDown() {
        StubURLProtocol.reset()
        service = nil
        super.tearDown()
    }

    func test_a_2xx_response_delivers_its_body() throws {
        let body = Data(#"{"status":"ok"}"#.utf8)
        StubURLProtocol.respond(status: 200, body: body, url: url)

        let data = try awaitValue(service.get(url: url))

        XCTAssertEqual(data, body)
    }

    /// FR-API-005 / NFR-DATA-003 — the defect this commit exists for. The catch-all stub
    /// answers 404 with a well-formed JSON body; before status validation that body was
    /// delivered as success data and handed to the decoder as if it were a user.
    func test_a_404_fails_and_its_body_is_not_delivered() throws {
        StubURLProtocol.respond(status: 404, body: Data(#"{"error":"User not found"}"#.utf8), url: url)

        let error = try awaitFailure(service.get(url: url))

        XCTAssertHttpStatus(error, 404)
    }

    func test_a_500_fails_with_its_status() throws {
        StubURLProtocol.respond(status: 500, url: url)

        let error = try awaitFailure(service.get(url: url))

        XCTAssertHttpStatus(error, 500)
    }

    /// 2xx is the only success band; a 3xx that reaches us is not silently accepted.
    func test_a_304_fails_with_its_status() throws {
        StubURLProtocol.respond(status: 304, url: url)

        let error = try awaitFailure(service.get(url: url))

        XCTAssertHttpStatus(error, 304)
    }

    /// The mountebank-is-down case: no response at all, which is what `.transport` is for.
    func test_a_transport_failure_is_reported_as_transport() throws {
        StubURLProtocol.fail(with: URLError(.cannotConnectToHost))

        let error = try awaitFailure(service.get(url: url))

        XCTAssertIsTransportFailure(error)
    }
}
