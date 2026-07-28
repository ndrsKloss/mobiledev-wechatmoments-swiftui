//
//  NetworkError.swift
//  WeChatMoments
//

import Foundation

/// The single failure type flowing out of the networking layer (`FAD-DATA-b`, `arch-spec §5.2`).
///
/// `URLError` — the previous failure type of `BaseService.get(url:)` — can describe a request
/// that never produced a response, but it has no case for "the server answered, and it said
/// 404". `FR-API-005` / `NFR-DATA-003` require exactly that distinction, because the mock's
/// catch-all stub returns a well-formed JSON body alongside its 404 status.
enum NetworkError: Error {
    /// No usable response: the host is unreachable, the request timed out, it was cancelled.
    case transport(URLError)
    /// A response arrived but was not an `HTTPURLResponse`, so its status cannot be read.
    case invalidResponse
    /// A response arrived with a non-2xx status. The body is deliberately discarded — it is
    /// an error payload, not data (`FR-API-005`).
    case httpStatus(Int)
    /// A 2xx body that the model could not read.
    case decoding(Error)
}

extension NetworkError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .transport(error):
            return error.localizedDescription
        case .invalidResponse:
            return "The server sent a response that could not be understood."
        case let .httpStatus(code):
            return "The server responded with status \(code)."
        case .decoding:
            return "The server's response did not match the expected format."
        }
    }
}
