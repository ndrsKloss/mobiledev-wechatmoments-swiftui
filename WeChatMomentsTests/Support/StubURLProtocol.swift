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
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let stub = StubURLProtocol.stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        switch stub {
        case let .success((response, data)):
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
