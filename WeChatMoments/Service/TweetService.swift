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

    init() {
        self.httpService = HttpService()
    }

    func getTweets(_ userName: String) -> AnyPublisher<[Tweet], Error> {
        let url = UrlConstant.tweetsUrl(name: userName)

        return httpService
            .get(url: url)
            // NFR-DATA-001 / FR-API-004: decode per element, so one malformed element
            // costs one tweet instead of the whole feed. See fn-spec §3.3.
            .decode(type: [FailableDecodable<Tweet>].self, decoder: JSONDecoder())
            .map { $0.compactMap(\.value) }
            .eraseToAnyPublisher()
    }
}
