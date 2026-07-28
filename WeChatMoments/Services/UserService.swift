//
//  UserService.swift
//  WeChatMoments
//
//  Created by nontapat.siengsanor on 23/2/24.
//

import Combine
import Foundation

class UserService {
    private var httpService: BaseService

    // NFR-TEST-001: see TweetService — same seam, same default argument.
    init(httpService: BaseService = HttpService()) {
        self.httpService = httpService
    }

    func getUserProfile(_ name: String) -> AnyPublisher<User, NetworkError> {
        let url = UrlConstant.userProfileUrl(name: name)

        return httpService
            .get(url: url)
            .decode(type: User.self, decoder: JSONDecoder())
            .mapError { error -> NetworkError in
                (error as? NetworkError) ?? .decoding(error)
            }
            .eraseToAnyPublisher()
    }
}
