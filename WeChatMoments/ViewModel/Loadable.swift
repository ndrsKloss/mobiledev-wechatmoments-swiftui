//
//  Loadable.swift
//  WeChatMoments
//
//  The shape `arch-spec §4.2` asks for: "an explicit state enum (idle / loading / loaded /
//  failed), which also gives NFR-DATA-005 somewhere to live".
//

import Foundation

/// One request's lifecycle, as a value.
///
/// The view model holds one of these per independent request rather than one for the screen,
/// which is what makes `FR-FEED-005` structural instead of a rule to remember: a completion can
/// only write its own property, so a failed profile cannot blank the feed.
///
/// Every case has a render path — `.idle`/`.loading` is the indicator (`FR-FEED-003`), `.loaded`
/// is the content, and `.failed` is the feed's error state (`FR-FEED-004`) or, for the profile,
/// the placeholder `FR-HEADER-002` already specifies. A case nothing draws would mean this enum
/// was the wrong size.
enum Loadable<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(NetworkError)

    var value: Value? {
        guard case let .loaded(value) = self else { return nil }
        return value
    }

    var isLoading: Bool {
        guard case .loading = self else { return false }
        return true
    }

    /// NFR-DATA-005: the error survives as a typed value the view can render, rather than being
    /// `print`ed and discarded.
    var error: NetworkError? {
        guard case let .failed(error) = self else { return nil }
        return error
    }

    /// FR-FEED-002: the guard that keeps a repeated `.onAppear` from re-requesting.
    var isIdle: Bool {
        guard case .idle = self else { return false }
        return true
    }
}
