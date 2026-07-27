//
//  Comment.swift
//  WeChatMoments
//

import Foundation

struct Comment: Decodable {
    let content: String?
    let sender: User?
}
