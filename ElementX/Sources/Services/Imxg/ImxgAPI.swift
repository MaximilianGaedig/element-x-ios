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
import MatrixRustSDK

/// Calls our tuwunel fork's `im.mxg.*` endpoints (and plain Matrix ones the SDK does not expose, like `/v3/search`)
/// with the session's own access token. The Rust SDK has no authenticated generic request (`Client.getUrl` sends no
/// token), so this uses `URLSession` with `Client.session()`, read again for every request because the SDK may
/// refresh the token at any time.
nonisolated protocol ImxgAPIProtocol: AnyObject, Sendable {
    /// Whether the homeserver advertises the feature (cached for `ImxgFeatureCache.lifetime`).
    func supports(_ feature: ImxgFeature) async -> Bool
    /// Forgets the cached features, for example after the server was upgraded.
    func invalidateFeatures() async

    func roomMedia(roomID: String, kind: ImxgMediaKind, limit: Int?, from: String?, beforeTimestamp: UInt64?, skip: Int?, months: Bool) async -> Result<ImxgRoomMediaPage, ImxgError>
    func allMedia(kind: ImxgMediaKind, limit: Int?, from: String?) async -> Result<ImxgAllMediaPage, ImxgError>
    func roomStats(roomID: String, senders: Int?) async -> Result<ImxgRoomStats, ImxgError>
    func activity(userID: String, fromTimestamp: UInt64?, toTimestamp: UInt64?, limit: Int?, week: Bool, utcOffsetMinutes: Int?, kinds: [String]?) async -> Result<ImxgActivity, ImxgError>
    func searchRoomEvents(term: String, roomIDs: [String]?, limit: Int?, nextBatch: String?) async -> Result<ImxgSearchResults, ImxgError>

    /// Any request, for endpoints without a typed wrapper yet.
    func send<Response: Decodable & Sendable>(_ request: ImxgRequest, requiring feature: ImxgFeature?, as type: Response.Type) async -> Result<Response, ImxgError>
}

nonisolated struct ImxgCredentials: Sendable {
    let accessToken: String
    let homeserverURL: String
}

actor ImxgAPI: ImxgAPIProtocol {
    typealias CredentialsProvider = @Sendable () throws -> ImxgCredentials
    /// Makes the SDK refresh an expired token: any authenticated SDK call does it when the session has a refresh token.
    typealias TokenRefresher = @Sendable () async -> Void
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let credentials: CredentialsProvider
    private let refreshToken: TokenRefresher
    private let transport: Transport
    private let now: @Sendable () -> Date

    private var featureCache = ImxgFeatureCache()
    private var featureTask: Task<Void, Never>?

    init(credentials: @escaping CredentialsProvider,
         refreshToken: @escaping TokenRefresher,
         transport: @escaping Transport = { try await URLSession.shared.data(for: $0) },
         now: @escaping @Sendable () -> Date = Date.init) {
        self.credentials = credentials
        self.refreshToken = refreshToken
        self.transport = transport
        self.now = now
    }

    /// Uses the SDK client's session. `Client.displayName()` is a cheap authenticated request that refreshes the token.
    init(client: ClientProtocol) {
        self.init(credentials: {
            let session = try client.session()
            return ImxgCredentials(accessToken: session.accessToken, homeserverURL: session.homeserverUrl)
        }, refreshToken: {
            _ = try? await client.displayName()
        })
    }

    // MARK: Features

    func supports(_ feature: ImxgFeature) async -> Bool {
        await refreshFeaturesIfNeeded()
        return featureCache.supports(feature)
    }

    func invalidateFeatures() {
        featureCache.invalidate()
    }

    private func refreshFeaturesIfNeeded() async {
        if let featureTask {
            await featureTask.value
            return
        }
        guard featureCache.needsRefresh(now: now()) else { return }
        let task = Task { await self.fetchFeatures() }
        featureTask = task
        await task.value
        featureTask = nil
    }

    private func fetchFeatures() async {
        switch await perform(.versions()) {
        case .success(let data):
            featureCache.store(ImxgResponse.enabledUnstableFeatures(versionsBody: data), now: now())
        case .failure(let error):
            MXLog.warning("im.mxg: /versions failed: \(error)")
            featureCache.storeFailure(now: now())
        }
    }

    // MARK: Endpoints

    func roomMedia(roomID: String, kind: ImxgMediaKind, limit: Int?, from: String?, beforeTimestamp: UInt64?, skip: Int?, months: Bool) async -> Result<ImxgRoomMediaPage, ImxgError> {
        await send(.roomMedia(roomID: roomID, kind: kind, limit: limit, from: from, beforeTimestamp: beforeTimestamp, skip: skip, months: months),
                   requiring: .mediaIndex, as: ImxgRoomMediaPage.self)
    }

    func allMedia(kind: ImxgMediaKind, limit: Int?, from: String?) async -> Result<ImxgAllMediaPage, ImxgError> {
        await send(.allMedia(kind: kind, limit: limit, from: from), requiring: .mediaIndex, as: ImxgAllMediaPage.self)
    }

    func roomStats(roomID: String, senders: Int?) async -> Result<ImxgRoomStats, ImxgError> {
        await send(.roomStats(roomID: roomID, senders: senders), requiring: .roomStats, as: ImxgRoomStats.self)
    }

    func activity(userID: String, fromTimestamp: UInt64?, toTimestamp: UInt64?, limit: Int?, week: Bool, utcOffsetMinutes: Int?, kinds: [String]?) async -> Result<ImxgActivity, ImxgError> {
        if kinds != nil, !(await supports(.activityKinds)) {
            return .failure(.unsupported(.activityKinds))
        }
        return await send(.activity(userID: userID, fromTimestamp: fromTimestamp, toTimestamp: toTimestamp, limit: limit,
                                    week: week, utcOffsetMinutes: utcOffsetMinutes, kinds: kinds),
                          requiring: .activity, as: ImxgActivity.self)
    }

    func searchRoomEvents(term: String, roomIDs: [String]?, limit: Int?, nextBatch: String?) async -> Result<ImxgSearchResults, ImxgError> {
        await send(.searchRoomEvents(term: term, roomIDs: roomIDs, limit: limit, nextBatch: nextBatch), requiring: nil, as: ImxgSearchResults.self)
    }

    func send<Response: Decodable & Sendable>(_ request: ImxgRequest, requiring feature: ImxgFeature?, as type: Response.Type) async -> Result<Response, ImxgError> {
        if let feature, !(await supports(feature)) {
            return .failure(.unsupported(feature))
        }
        switch await perform(request) {
        case .success(let data):
            do {
                return try .success(JSONDecoder().decode(Response.self, from: data))
            } catch {
                return .failure(.decoding(String(describing: error)))
            }
        case .failure(let error):
            return .failure(error)
        }
    }

    // MARK: Transport

    /// Sends the request; on a 401 for an expired token, lets the SDK refresh it and sends it once more.
    private func perform(_ request: ImxgRequest) async -> Result<Data, ImxgError> {
        var refreshed = false
        while true {
            let credentials: ImxgCredentials
            do {
                credentials = try self.credentials()
            } catch {
                return .failure(.noSession)
            }
            guard let urlRequest = request.urlRequest(homeserver: credentials.homeserverURL, accessToken: credentials.accessToken) else {
                return .failure(.invalidURL)
            }
            let data: Data
            let status: Int
            do {
                let (body, response) = try await transport(urlRequest)
                data = body
                status = (response as? HTTPURLResponse)?.statusCode ?? 0
            } catch {
                return .failure(.transport(String(describing: error)))
            }
            if (200..<300).contains(status) {
                return .success(data)
            }
            if !refreshed, request.authenticated, ImxgResponse.shouldRetryAfterRefreshingToken(status: status, data: data) {
                refreshed = true
                await refreshToken()
                continue
            }
            return .failure(ImxgResponse.error(status: status, data: data))
        }
    }
}

nonisolated extension ImxgAPIProtocol {
    func roomMedia(roomID: String, kind: ImxgMediaKind, limit: Int? = nil, from: String? = nil) async -> Result<ImxgRoomMediaPage, ImxgError> {
        await roomMedia(roomID: roomID, kind: kind, limit: limit, from: from, beforeTimestamp: nil, skip: nil, months: false)
    }

    func mediaMonths(roomID: String, kind: ImxgMediaKind) async -> Result<ImxgRoomMediaPage, ImxgError> {
        await roomMedia(roomID: roomID, kind: kind, limit: nil, from: nil, beforeTimestamp: nil, skip: nil, months: true)
    }
}
