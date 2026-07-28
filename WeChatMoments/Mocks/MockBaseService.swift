//
//  MockBaseService.swift
//  WeChatMoments
//

#if DEBUG
import Combine
import Foundation

/// Test double for the network seam (`arch-spec §10.3`, `NFR-TEST-001/007`). Lives in the app
/// target so previews and tests share it; it contains no production logic.
final class MockBaseService: BaseService {

    /// Every URL `get(url:)` was asked for, in order — this is how the tests assert that a
    /// feature service built the endpoint it claims to.
    private(set) var requestedUrls: [URL] = []

    /// What the next — and every — call returns. Configurable per instance.
    var result: Result<Data, NetworkError>

    var callCount: Int { requestedUrls.count }

    init(result: Result<Data, NetworkError> = .success(Data())) {
        self.result = result
    }

    convenience init(json: String) {
        self.init(result: .success(Data(json.utf8)))
    }

    func get(url: URL) -> AnyPublisher<Data, NetworkError> {
        requestedUrls.append(url)
        return result.publisher.eraseToAnyPublisher()
    }
}
#endif
