//
//  StubURLProtocol.swift
//  WeChatMomentsTests
//
//  Lets HttpService be tested against a scripted HTTP response with no server and no network
//  (NFR-TEST-002). It is installed on an ephemeral URLSessionConfiguration and injected
//  through the `init(urlSession:)` seam HttpService already had.
//

import Foundation

final class StubURLProtocol: URLProtocol {

    /// What the next request receives. Set before making the request, cleared in tearDown.
    /// Static because `URLProtocol` instances are created by the loading system, not by us.
    nonisolated(unsafe) static var stub: Result<(HTTPURLResponse, Data), Error>?

    /// How many requests actually reached the loading system. This is what lets ImageLoaderTests
    /// prove a cache hit was served *without* a second fetch (NFR-PERF-003) — an assertion about
    /// the returned image alone could not tell the two apart.
    nonisolated(unsafe) private(set) static var requestCount = 0

    /// Holds a response open. Without it a stub answers synchronously, so two "concurrent"
    /// requests can never actually overlap and a coalescing assertion would be satisfied by the
    /// cache instead (`NFR-PERF-006`).
    nonisolated(unsafe) static var responseDelay: TimeInterval = 0

    /// A session wired to this protocol and nothing else.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func respond(status: Int, body: Data = Data(), url: URL) {
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        stub = .success((response, body))
    }

    static func fail(with error: Error) {
        stub = .failure(error)
    }

    static func reset() {
        stub = nil
        requestCount = 0
        responseDelay = 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.requestCount += 1

        let deliver = { [weak self] in
            guard let self else { return }

            guard let stub = StubURLProtocol.stub else {
                self.client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
                return
            }

            switch stub {
            case let .success((response, data)):
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data)
                self.client?.urlProtocolDidFinishLoading(self)
            case let .failure(error):
                self.client?.urlProtocol(self, didFailWithError: error)
            }
        }

        if StubURLProtocol.responseDelay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + StubURLProtocol.responseDelay, execute: deliver)
        } else {
            deliver()
        }
    }

    override func stopLoading() {}
}
