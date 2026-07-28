//
//  Mountebank.swift
//  WeChatMomentsTests
//
//  FAD-TEST-a: integration tests are identified by folder and by name, and open with
//  `try XCTSkipUnless(Mountebank.isReachable)` so the offline suite (NFR-TEST-002) stays green
//  when the mock server is not running — a skip rather than a failure.
//

import Foundation

enum Mountebank {

    static let host = URL(string: TestDataConfig.URL_HOST)!

    /// A short, blocking probe of `localhost:2727`. A refused connection on loopback fails
    /// immediately, so this costs nothing when the server is down.
    static var isReachable: Bool {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        let session = URLSession(configuration: configuration)

        var reachable = false
        let done = DispatchSemaphore(value: 0)

        session.dataTask(with: host) { _, response, _ in
            reachable = response != nil
            done.signal()
        }.resume()

        _ = done.wait(timeout: .now() + 3)
        return reachable
    }
}
