//
// Copyright 2026 Maximilian Gaedig.
//
// SPDX-License-Identifier: AGPL-3.0-only
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing

struct ImxgRequestTests {
    @Test
    func escapesRoomIDsInPaths() {
        let request = ImxgRequest.roomMedia(roomID: "!abc/def:mxg.sh", kind: .voice, limit: 50, from: "t1_2+3")
        #expect(request.url(homeserver: "https://matrix.mxg.sh")?.absoluteString
            == "https://matrix.mxg.sh/_matrix/client/unstable/im.mxg.media_index/rooms/%21abc%2Fdef%3Amxg.sh/media?kind=voice&limit=50&from=t1_2%2B3")
    }

    @Test
    func keepsTheHomeserverPathPrefix() {
        let request = ImxgRequest.roomStats(roomID: "!r:s")
        #expect(request.url(homeserver: "https://example.org/matrix/")?.absoluteString
            == "https://example.org/matrix/_matrix/client/unstable/im.mxg.stats/rooms/%21r%3As")
    }

    @Test
    func monthsAndPlaces() {
        let request = ImxgRequest.roomMedia(roomID: "!r:s", kind: .media, beforeTimestamp: 1_700_000_000_000, skip: 3, months: true)
        #expect(request.url(homeserver: "https://h")?.query == "kind=media&before_ts=1700000000000&skip=3&months=true")
    }

    @Test
    func activityWeekWithKinds() {
        let request = ImxgRequest.activity(userID: "@a:s", week: true, utcOffsetMinutes: -120, kinds: ["online", "seen"])
        #expect(request.url(homeserver: "https://h")?.absoluteString
            == "https://h/_matrix/client/unstable/im.mxg.activity/users/%40a%3As?week=true&utc_offset_minutes=-120&kinds=online%2Cseen")
    }

    @Test
    func searchBody() throws {
        let request = ImxgRequest.searchRoomEvents(term: "hi", roomIDs: ["!r:s"], limit: 10, nextBatch: "b")
        #expect(request.method == .post)
        #expect(request.url(homeserver: "https://h")?.absoluteString == "https://h/_matrix/client/v3/search?next_batch=b")
        let body = try #require(request.body.flatMap { String(data: $0, encoding: .utf8) })
        #expect(body == #"{"search_categories":{"room_events":{"filter":{"limit":10,"rooms":["!r:s"]},"order_by":"recent","search_term":"hi"}}}"#)
    }

    @Test
    func authorizationHeader() {
        let request = ImxgRequest.versions().urlRequest(homeserver: "https://h", accessToken: "tok")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    }
}

struct ImxgResponseTests {
    @Test
    func enabledFeaturesOnly() {
        let body = Data(#"{"versions":["v1.11"],"unstable_features":{"im.mxg.media_index":true,"im.mxg.activity":false,"org.x":true}}"#.utf8)
        #expect(ImxgResponse.enabledUnstableFeatures(versionsBody: body) == ["im.mxg.media_index", "org.x"])
        #expect(ImxgResponse.enabledUnstableFeatures(versionsBody: Data("nope".utf8)) == [])
    }

    @Test
    func retriesOnlyExpiredTokens() {
        let unknownToken = Data(#"{"errcode":"M_UNKNOWN_TOKEN","error":"x","soft_logout":true}"#.utf8)
        #expect(ImxgResponse.shouldRetryAfterRefreshingToken(status: 401, data: unknownToken))
        #expect(ImxgResponse.shouldRetryAfterRefreshingToken(status: 401, data: Data()))
        #expect(!ImxgResponse.shouldRetryAfterRefreshingToken(status: 403, data: unknownToken))
        #expect(!ImxgResponse.shouldRetryAfterRefreshingToken(status: 401, data: Data(#"{"errcode":"M_FORBIDDEN"}"#.utf8)))
    }

    @Test
    func featureCacheExpiresAndBacksOff() {
        let start = Date(timeIntervalSince1970: 1000)
        var cache = ImxgFeatureCache()
        #expect(cache.needsRefresh(now: start))
        cache.storeFailure(now: start)
        #expect(!cache.needsRefresh(now: start.addingTimeInterval(30)))
        #expect(cache.needsRefresh(now: start.addingTimeInterval(61)))
        cache.store(["im.mxg.room_stats"], now: start)
        #expect(cache.supports(.roomStats))
        #expect(!cache.supports(.mediaIndex))
        #expect(!cache.needsRefresh(now: start.addingTimeInterval(3599)))
        #expect(cache.needsRefresh(now: start.addingTimeInterval(3600)))
        cache.invalidate()
        #expect(!cache.supports(.roomStats))
    }
}

struct ImxgModelTests {
    @Test
    func decodesRoomMediaWithMonths() throws {
        let json = #"""
        {"chunk":[{"event_id":"$e","type":"m.room.message","sender":"@a:s","origin_server_ts":5,"room_id":"!r:s",
          "content":{"msgtype":"m.image","body":"x.jpg","info":{"w":10}}}],
         "end":"5_ab","positions":[0],"next_position":1,"months":[{"month":"2026-10","count":3,"before_ts":99}]}
        """#
        let page = try JSONDecoder().decode(ImxgRoomMediaPage.self, from: Data(json.utf8))
        #expect(page.chunk.first?.content["msgtype"]?.stringValue == "m.image")
        #expect(page.chunk.first?.content["info"]?["w"]?.numberValue == 10)
        #expect(page.chunk.first?.raw["room_id"]?.stringValue == "!r:s")
        #expect(page.end == "5_ab")
        #expect(page.nextPosition == 1)
        #expect(page.months == [.init(month: "2026-10", count: 3, beforeTimestamp: 99)])
    }

    @Test
    func decodesStats() throws {
        let json = #"""
        {"storage":{"events":10,"media_stored":2,"media_on_demand":1},"total":10,"by_kind":{"text":8,"image":2},
         "senders":[{"user_id":"@a:s","total":10,"by_kind":{"text":8}}],"sender_count":1,"first_ts":1,"last_ts":2,
         "complete":true,"by_month":[{"month":"2026-10","count":10}],"by_hour_of_week":[0,1]}
        """#
        let stats = try JSONDecoder().decode(ImxgRoomStats.self, from: Data(json.utf8))
        #expect(stats.byKind["image"] == 2)
        #expect(stats.senders.first?.userID == "@a:s")
        #expect(stats.storage.mediaOnDemand == 1)
    }

    @Test
    func decodesActivityWeek() throws {
        let json = #"{"chunk":[],"week":{"seen":[[1]],"online_ms":[[2]],"days":[1],"entries":4}}"#
        let activity = try JSONDecoder().decode(ImxgActivity.self, from: Data(json.utf8))
        #expect(activity.week?.onlineMilliseconds == [[2]])
        #expect(activity.week?.entries == 4)
    }

    @Test
    func decodesSearch() throws {
        let json = #"""
        {"search_categories":{"room_events":{"count":1,"highlights":["hi"],"next_batch":"n",
          "results":[{"rank":1.5,"result":{"event_id":"$e","type":"m.room.message","sender":"@a:s","origin_server_ts":1,"content":{}}}]}}}
        """#
        let results = try JSONDecoder().decode(ImxgSearchResults.self, from: Data(json.utf8))
        #expect(results.results.first?.event.eventID == "$e")
        #expect(results.nextBatch == "n")
    }
}

/// Records requests and answers them from a script.
private final class ScriptedTransport: @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [(path: String, status: Int, body: String)]
    private(set) var requests: [URLRequest] = []

    init(_ answers: [(String, Int, String)]) {
        self.answers = answers.map { (path: $0.0, status: $0.1, body: $0.2) }
    }

    func handle(_ request: URLRequest) throws -> (Data, URLResponse) {
        lock.lock()
        defer { lock.unlock() }
        requests.append(request)
        guard let index = answers.firstIndex(where: { request.url?.path.hasSuffix($0.path) == true }) else {
            throw URLError(.badServerResponse)
        }
        let answer = answers.remove(at: index)
        let response = HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: nil, headerFields: nil)!
        return (Data(answer.body.utf8), response)
    }

    var paths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return requests.compactMap { $0.url?.path }
    }
}

private final class TokenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var token = "old"
    private(set) var refreshes = 0

    var current: String {
        lock.lock()
        defer { lock.unlock() }
        return token
    }

    func refresh() {
        lock.lock()
        defer { lock.unlock() }
        refreshes += 1
        token = "new"
    }
}

struct ImxgAPITests {
    private static let versions = #"{"versions":[],"unstable_features":{"im.mxg.room_stats":true}}"#
    private static let stats = #"""
    {"storage":{"events":1,"media_stored":0,"media_on_demand":0},"total":1,"by_kind":{},"senders":[],"sender_count":0,
     "complete":true,"by_month":[],"by_hour_of_week":[]}
    """#

    private func makeAPI(_ transport: ScriptedTransport, tokens: TokenBox) -> ImxgAPI {
        ImxgAPI(credentials: { ImxgCredentials(accessToken: tokens.current, homeserverURL: "https://h") },
                refreshToken: { tokens.refresh() },
                transport: { try transport.handle($0) })
    }

    @Test
    func refreshesTheTokenOnceAfterA401() async throws {
        let transport = ScriptedTransport([("/versions", 200, Self.versions),
                                           ("/rooms/!r:s", 401, #"{"errcode":"M_UNKNOWN_TOKEN","soft_logout":true}"#),
                                           ("/rooms/!r:s", 200, Self.stats)])
        let tokens = TokenBox()
        let result = await makeAPI(transport, tokens: tokens).roomStats(roomID: "!r:s", senders: nil)
        #expect((try? result.get())?.total == 1)
        #expect(tokens.refreshes == 1)
        let auth = transport.requests.map { $0.value(forHTTPHeaderField: "Authorization") }
        #expect(auth == ["Bearer old", "Bearer old", "Bearer new"])
    }

    @Test
    func givesUpAfterOneRetry() async {
        let transport = ScriptedTransport([("/versions", 200, Self.versions),
                                           ("/rooms/!r:s", 401, #"{"errcode":"M_UNKNOWN_TOKEN"}"#),
                                           ("/rooms/!r:s", 401, #"{"errcode":"M_UNKNOWN_TOKEN","error":"gone"}"#)])
        let tokens = TokenBox()
        let result = await makeAPI(transport, tokens: tokens).roomStats(roomID: "!r:s", senders: nil)
        #expect(result == .failure(.server(status: 401, errcode: "M_UNKNOWN_TOKEN", message: "gone")))
        #expect(tokens.refreshes == 1)
        #expect(transport.requests.count == 3)
    }

    @Test
    func unsupportedFeaturesNeverHitTheServer() async {
        let transport = ScriptedTransport([("/versions", 200, Self.versions)])
        let api = makeAPI(transport, tokens: TokenBox())
        let media = await api.roomMedia(roomID: "!r:s", kind: .media)
        #expect(media == .failure(.unsupported(.mediaIndex)))
        let activity = await api.activity(userID: "@a:s", fromTimestamp: nil, toTimestamp: nil, limit: nil, week: true, utcOffsetMinutes: nil, kinds: nil)
        #expect(activity == .failure(.unsupported(.activity)))
        #expect(transport.paths == ["/_matrix/client/versions"])
    }

    @Test
    func concurrentCallsShareOneVersionsRequest() async {
        let transport = ScriptedTransport([("/versions", 200, Self.versions)])
        let api = makeAPI(transport, tokens: TokenBox())
        async let first = api.supports(.roomStats)
        async let second = api.supports(.roomStats)
        async let third = api.supports(.mediaIndex)
        let answers = await [first, second, third]
        #expect(answers == [true, true, false])
        #expect(transport.paths == ["/_matrix/client/versions"])
    }

    @Test
    func noSessionIsAnError() async {
        let api = ImxgAPI(credentials: { throw ImxgError.noSession }, refreshToken: { }, transport: { _ in throw URLError(.cancelled) })
        #expect(await api.supports(.roomStats) == false)
        #expect(await api.roomStats(roomID: "!r:s", senders: nil) == .failure(.unsupported(.roomStats)))
    }
}
