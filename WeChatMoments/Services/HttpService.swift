//
//  HttpService.swift
//  WeChatMoments
//
//  Created by nontapat.siengsanor on 23/2/24.
//

import Combine
import Foundation

protocol BaseService {
    func get(url: URL) -> AnyPublisher<Data, NetworkError>
}

class HttpService: BaseService {
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func get(url: URL) -> AnyPublisher<Data, NetworkError> {
        return urlSession
            .dataTaskPublisher(for: url)
            // NFR-DATA-003 / FR-API-005: the status is validated here, at the single
            // URLSession boundary, so no feature service repeats it. This was `.map(\.data)`,
            // which discarded the response entirely and handed the catch-all stub's 404 body
            // to the decoder as if it were a successful payload.
            .tryMap { data, response in
                guard let response = response as? HTTPURLResponse else {
                    throw NetworkError.invalidResponse
                }
                guard (200..<300).contains(response.statusCode) else {
                    throw NetworkError.httpStatus(response.statusCode)
                }
                return data
            }
            .mapError { error in
                switch error {
                case let error as NetworkError: return error
                case let error as URLError: return .transport(error)
                default: return .invalidResponse
                }
            }
            .eraseToAnyPublisher()
    }
}
