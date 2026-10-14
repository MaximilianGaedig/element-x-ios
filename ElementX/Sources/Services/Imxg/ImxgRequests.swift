//
// Copyright 2026 Maximilian Gaedig.
//
// SPDX-License-Identifier: AGPL-3.0-only
// Please see LICENSE files in the repository root for full details.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking // Linux, for the unit tests
#endif

/// The `im.mxg.*` features our tuwunel fork advertises in `/_matrix/client/versions` `unstable_features`
/// (tuwunel `src/api/client/versions.rs`). Every call checks its flag first: other homeservers have none of them.
nonisolated enum ImxgFeature: String, CaseIterable, Sendable {
    case activity = "im.mxg.activity"
    case activityKinds = "im.mxg.activity.kinds"
    case export = "im.mxg.export"
    case mediaIndex = "im.mxg.media_index"
    case mediaText = "im.mxg.media_text"
    case roomStats = "im.mxg.room_stats"
    case storage = "im.mxg.storage"
    case typingKinds = "im.mxg.typing_kinds"
    case presenceExtension = "im.mxg.msc4186.presence"
    case previewExtension = "im.mxg.msc4186.preview"
    case userDirectorySearch = "im.mxg.user_directory_search"
}

/// The kinds `im.mxg.media_index` lists (tuwunel `src/api/client/media_index.rs`).
nonisolated enum ImxgMediaKind: String, CaseIterable, Sendable {
    case media, files, links, music, voice, calls
}

nonisolated enum ImxgHTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
}

/// A request to the homeserver, before the base URL and the token are known.
nonisolated struct ImxgRequest: Equatable, Sendable {
    var method: ImxgHTTPMethod = .get
    /// Path segments after the host, each escaped separately (room and user IDs contain `!`, `:`, `@`, `#`, `/`).
    var pathSegments: [String]
    var query: [URLQueryItem] = []
    var body: Data?
    /// Whether to send the access token. `/versions` works without it, but tuwunel may answer per user.
    var authenticated = true

    /// The full URL for a homeserver base URL (with or without a trailing slash or a path prefix).
    func url(homeserver: String) -> URL? {
        guard var components = URLComponents(string: homeserver) else { return nil }
        var basePath = components.percentEncodedPath
        while basePath.hasSuffix("/") {
            basePath.removeLast()
        }
        let escaped = pathSegments.map(Self.escapePathSegment).joined(separator: "/")
        components.percentEncodedPath = basePath + "/" + escaped
        if !query.isEmpty {
            // URLComponents leaves `+` alone in queries, which servers read as a space.
            components.percentEncodedQuery = query.map { item in
                Self.escapeQuery(item.name) + (item.value.map { "=" + Self.escapeQuery($0) } ?? "")
            }.joined(separator: "&")
        }
        return components.url
    }

    func urlRequest(homeserver: String, accessToken: String?) -> URLRequest? {
        guard let url = url(homeserver: homeserver) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        if authenticated, let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func escapePathSegment(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: unreserved) ?? segment
    }

    static func escapeQuery(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }
}

// MARK: - Endpoints

nonisolated extension ImxgRequest {
    private static let clientPrefix = ["_matrix", "client"]

    static func versions() -> ImxgRequest {
        ImxgRequest(pathSegments: clientPrefix + ["versions"])
    }

    /// `GET /_matrix/client/unstable/im.mxg.media_index/rooms/{roomId}/media` (feature `im.mxg.media_index`).
    /// `beforeTimestamp` (ms) opens the list at a date; `skip` with it returns `positions`; `months` returns the month counts.
    static func roomMedia(roomID: String,
                          kind: ImxgMediaKind,
                          limit: Int? = nil,
                          from: String? = nil,
                          beforeTimestamp: UInt64? = nil,
                          skip: Int? = nil,
                          months: Bool = false) -> ImxgRequest {
        var query = [URLQueryItem(name: "kind", value: kind.rawValue)]
        query.appendIfPresent("limit", limit.map(String.init))
        query.appendIfPresent("from", from)
        query.appendIfPresent("before_ts", beforeTimestamp.map(String.init))
        query.appendIfPresent("skip", skip.map(String.init))
        if months { query.append(URLQueryItem(name: "months", value: "true")) }
        return ImxgRequest(pathSegments: clientPrefix + ["unstable", "im.mxg.media_index", "rooms", roomID, "media"], query: query)
    }

    /// `GET /_matrix/client/unstable/im.mxg.media_index/media`: one kind across every room (feature `im.mxg.media_index`).
    static func allMedia(kind: ImxgMediaKind, limit: Int? = nil, from: String? = nil) -> ImxgRequest {
        var query = [URLQueryItem(name: "kind", value: kind.rawValue)]
        query.appendIfPresent("limit", limit.map(String.init))
        query.appendIfPresent("from", from)
        return ImxgRequest(pathSegments: clientPrefix + ["unstable", "im.mxg.media_index", "media"], query: query)
    }

    /// `GET /_matrix/client/unstable/im.mxg.stats/rooms/{roomId}` (feature `im.mxg.room_stats`).
    static func roomStats(roomID: String, senders: Int? = nil) -> ImxgRequest {
        var query: [URLQueryItem] = []
        query.appendIfPresent("senders", senders.map(String.init))
        return ImxgRequest(pathSegments: clientPrefix + ["unstable", "im.mxg.stats", "rooms", roomID], query: query)
    }

    /// `GET /_matrix/client/unstable/im.mxg.activity/users/{userId}` (feature `im.mxg.activity`; `kinds` needs
    /// `im.mxg.activity.kinds`). With `week`, the hours of their week in the asker's time zone instead of rows.
    static func activity(userID: String,
                         fromTimestamp: UInt64? = nil,
                         toTimestamp: UInt64? = nil,
                         limit: Int? = nil,
                         week: Bool = false,
                         utcOffsetMinutes: Int? = nil,
                         kinds: [String]? = nil) -> ImxgRequest {
        var query: [URLQueryItem] = []
        query.appendIfPresent("from_ts", fromTimestamp.map(String.init))
        query.appendIfPresent("to_ts", toTimestamp.map(String.init))
        query.appendIfPresent("limit", limit.map(String.init))
        if week { query.append(URLQueryItem(name: "week", value: "true")) }
        query.appendIfPresent("utc_offset_minutes", utcOffsetMinutes.map(String.init))
        query.appendIfPresent("kinds", kinds.map { $0.joined(separator: ",") })
        return ImxgRequest(pathSegments: clientPrefix + ["unstable", "im.mxg.activity", "users", userID], query: query)
    }

    /// `POST /_matrix/client/v3/search` for room events, served by tuwunel's tantivy index.
    static func searchRoomEvents(term: String, roomIDs: [String]? = nil, limit: Int? = nil, nextBatch: String? = nil) -> ImxgRequest {
        var filter: [String: Any] = [:]
        if let roomIDs { filter["rooms"] = roomIDs }
        if let limit { filter["limit"] = limit }
        var roomEvents: [String: Any] = ["search_term": term, "order_by": "recent"]
        if !filter.isEmpty { roomEvents["filter"] = filter }
        let body = try? JSONSerialization.data(withJSONObject: ["search_categories": ["room_events": roomEvents]], options: [.sortedKeys])
        var query: [URLQueryItem] = []
        query.appendIfPresent("next_batch", nextBatch)
        return ImxgRequest(method: .post, pathSegments: clientPrefix + ["v3", "search"], query: query, body: body)
    }
}

private nonisolated extension [URLQueryItem] {
    mutating func appendIfPresent(_ name: String, _ value: String?) {
        if let value { append(URLQueryItem(name: name, value: value)) }
    }
}

// MARK: - Responses and errors

nonisolated enum ImxgError: Error, Equatable {
    /// The homeserver does not advertise the feature: fall back to Element X's own behaviour.
    case unsupported(ImxgFeature)
    case noSession
    case invalidURL
    /// A Matrix error (`errcode`, `error`) or a bare HTTP status.
    case server(status: Int, errcode: String?, message: String?)
    case decoding(String)
    case transport(String)
}

nonisolated enum ImxgResponse {
    /// The Matrix error body of a failed response, if it has one.
    static func error(status: Int, data: Data) -> ImxgError {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return .server(status: status, errcode: object?["errcode"] as? String, message: object?["error"] as? String)
    }

    /// A 401 with `M_UNKNOWN_TOKEN` (or none) means the token expired or was refreshed under us: refresh it and try once more.
    /// `soft_logout: false` with `M_UNKNOWN_TOKEN` is a real logout, which the SDK handles; retrying once is still harmless.
    static func shouldRetryAfterRefreshingToken(status: Int, data: Data) -> Bool {
        guard status == 401 else { return false }
        guard case let .server(_, errcode, _) = error(status: status, data: data) else { return false }
        return errcode == nil || errcode == "M_UNKNOWN_TOKEN" || errcode == "M_MISSING_TOKEN"
    }

    /// The `unstable_features` of a `/versions` body that are switched on.
    static func enabledUnstableFeatures(versionsBody data: Data) -> Set<String> {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let features = object["unstable_features"] as? [String: Any] else {
            return []
        }
        return Set(features.compactMap { key, value in (value as? Bool) == true ? key : nil })
    }
}

/// When the cached `unstable_features` must be read again. A server upgrade adds features, so the cache expires.
nonisolated struct ImxgFeatureCache: Sendable {
    static let lifetime: TimeInterval = 60 * 60
    /// After a failed `/versions`, wait before asking again instead of on every call.
    static let failureBackoff: TimeInterval = 60

    private(set) var features: Set<String>?
    private(set) var fetchedAt: Date?
    private(set) var failedAt: Date?

    func needsRefresh(now: Date) -> Bool {
        if let failedAt, now.timeIntervalSince(failedAt) < Self.failureBackoff { return false }
        guard let fetchedAt, features != nil else { return true }
        return now.timeIntervalSince(fetchedAt) >= Self.lifetime
    }

    mutating func store(_ features: Set<String>, now: Date) {
        self.features = features
        fetchedAt = now
        failedAt = nil
    }

    mutating func storeFailure(now: Date) {
        failedAt = now
    }

    mutating func invalidate() {
        features = nil
        fetchedAt = nil
        failedAt = nil
    }

    func supports(_ feature: ImxgFeature) -> Bool {
        features?.contains(feature.rawValue) ?? false
    }
}
