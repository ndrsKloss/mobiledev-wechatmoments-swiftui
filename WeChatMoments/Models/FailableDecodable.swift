//
//  FailableDecodable.swift
//  WeChatMoments
//

import Foundation

/// Decodes `Wrapped`, or `nil` if `Wrapped` throws.
///
/// `JSONDecoder` fails a container atomically: one malformed element in an array aborts the
/// whole decode. Decoding `[FailableDecodable<T>]` and compact-mapping the results instead
/// costs one element per failure rather than the entire response (`NFR-DATA-001`, `FR-API-004`).
struct FailableDecodable<Wrapped: Decodable>: Decodable {
    let value: Wrapped?

    init(from decoder: Decoder) throws {
        value = try? Wrapped(from: decoder)
    }
}
