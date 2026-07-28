//
//  TweetService.swift
//  WeChatMoments
//
//  Created by nontapat.siengsanor on 23/2/24.
//

import Combine
import Foundation

class TweetService {
    private var httpService: BaseService

    // NFR-TEST-001: the default argument supplies production behaviour, so no call site
    // changes, while tests and previews can pass a MockBaseService.
    init(httpService: BaseService = HttpService()) {
        self.httpService = httpService
    }

    func getTweets(_ userName: String) -> AnyPublisher<[Tweet], NetworkError> {
        let url = UrlConstant.tweetsUrl(name: userName)

        return httpService
            .get(url: url)
            // NFR-DATA-001 / FR-API-004: decode per element, so one malformed element
            // costs one tweet instead of the whole feed. See fn-spec §3.3.
            .decode(type: [FailableDecodable<Tweet>].self, decoder: JSONDecoder())
            .map { $0.compactMap(\.value) }
            // `decode` widens the failure type to `Error`; narrow it back. A transport or
            // status failure passes through untouched, anything else came from the decoder.
            .mapError { error -> NetworkError in
                (error as? NetworkError) ?? .decoding(error)
            }
            .eraseToAnyPublisher()
    }
}
