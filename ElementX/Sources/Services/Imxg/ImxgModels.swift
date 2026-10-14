//
// Copyright 2026 Maximilian Gaedig.
//
// SPDX-License-Identifier: AGPL-3.0-only
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// Any JSON value, for raw Matrix events (the media index returns events, not a fixed shape).
nonisolated enum ImxgJSON: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([ImxgJSON])
    case object([String: ImxgJSON])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([ImxgJSON].self) {
            self = .array(value)
        } else {
            self = try .object(container.decode([String: ImxgJSON].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    subscript(key: String) -> ImxgJSON? {
        if case let .object(object) = self { return object[key] }
        return nil
    }

    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    var numberValue: Double? {
        if case let .number(value) = self { return value }
        return nil
    }
}

/// A raw timeline event as the server sent it.
nonisolated struct ImxgEvent: Decodable, Equatable, Sendable {
    let eventID: String
    let type: String
    let sender: String
    let originServerTimestamp: UInt64
    let roomID: String?
    let content: ImxgJSON
    /// The whole event, for code that needs more than the fields above.
    let raw: ImxgJSON

    private enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case type
        case sender
        case originServerTimestamp = "origin_server_ts"
        case roomID = "room_id"
        case content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eventID = try container.decode(String.self, forKey: .eventID)
        type = try container.decode(String.self, forKey: .type)
        sender = try container.decode(String.self, forKey: .sender)
        originServerTimestamp = try container.decode(UInt64.self, forKey: .originServerTimestamp)
        roomID = try container.decodeIfPresent(String.self, forKey: .roomID)
        content = try container.decodeIfPresent(ImxgJSON.self, forKey: .content) ?? .object([:])
        raw = try ImxgJSON(from: decoder)
    }
}

/// `im.mxg.media_index/rooms/{roomId}/media` (tuwunel `src/api/client/media_index.rs`).
nonisolated struct ImxgRoomMediaPage: Decodable, Equatable, Sendable {
    /// Newest first.
    let chunk: [ImxgEvent]
    let end: String?
    /// With `skip`: each event's place in the whole list; a missing place is redacted or hidden.
    let positions: [UInt64]?
    let nextPosition: UInt64?
    /// With `months=true`: newest first.
    let months: [ImxgMonthCount]

    struct ImxgMonthCount: Decodable, Equatable, Sendable {
        /// `YYYY-MM`.
        let month: String
        let count: Int
        /// Opens the list at this month.
        let beforeTimestamp: UInt64

        private enum CodingKeys: String, CodingKey {
            case month, count
            case beforeTimestamp = "before_ts"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case chunk, end, positions, months
        case nextPosition = "next_position"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        chunk = try container.decodeIfPresent([ImxgEvent].self, forKey: .chunk) ?? []
        end = try container.decodeIfPresent(String.self, forKey: .end)
        positions = try container.decodeIfPresent([UInt64].self, forKey: .positions)
        nextPosition = try container.decodeIfPresent(UInt64.self, forKey: .nextPosition)
        months = try container.decodeIfPresent([ImxgMonthCount].self, forKey: .months) ?? []
    }
}

/// `im.mxg.media_index/media` (tuwunel `src/api/client/media_all.rs`): `rooms[i]` is the room of `chunk[i]`.
nonisolated struct ImxgAllMediaPage: Decodable, Equatable, Sendable {
    let chunk: [ImxgEvent]
    let rooms: [String]
    let end: String?
}

/// `im.mxg.stats/rooms/{roomId}` (tuwunel `src/api/client/room_stats.rs`).
nonisolated struct ImxgRoomStats: Decodable, Equatable, Sendable {
    struct Storage: Decodable, Equatable, Sendable {
        let events: UInt64
        let mediaStored: UInt64
        let mediaOnDemand: UInt64

        private enum CodingKeys: String, CodingKey {
            case events
            case mediaStored = "media_stored"
            case mediaOnDemand = "media_on_demand"
        }
    }

    struct Sender: Decodable, Equatable, Sendable {
        let userID: String
        let total: UInt64
        let byKind: [String: UInt64]

        private enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case total
            case byKind = "by_kind"
        }
    }

    struct MonthCount: Decodable, Equatable, Sendable {
        let month: String
        let count: UInt64
    }

    let storage: Storage
    let total: UInt64
    /// `text`, `image`, `video`, `audio`, `voice`, `file`, `sticker`, `link`.
    let byKind: [String: UInt64]
    let senders: [Sender]
    let senderCount: UInt64
    let firstTimestamp: UInt64?
    let lastTimestamp: UInt64?
    /// False while the server is still counting old history.
    let complete: Bool
    let byMonth: [MonthCount]
    /// 168 hours from Monday 00:00 UTC.
    let byHourOfWeek: [UInt64]

    private enum CodingKeys: String, CodingKey {
        case storage, total, senders, complete
        case byKind = "by_kind"
        case senderCount = "sender_count"
        case firstTimestamp = "first_ts"
        case lastTimestamp = "last_ts"
        case byMonth = "by_month"
        case byHourOfWeek = "by_hour_of_week"
    }
}

/// `im.mxg.activity/users/{userId}` (tuwunel `src/api/client/activity.rs`).
nonisolated struct ImxgActivity: Decodable, Equatable, Sendable {
    struct Row: Decodable, Equatable, Sendable {
        let timestamp: UInt64
        /// `online`, `unavailable`, `offline`, `seen`, `sent`, `reaction`, ...
        let kind: String
        let roomID: String?
        let lastActiveTimestamp: UInt64?

        private enum CodingKeys: String, CodingKey {
            case timestamp = "ts"
            case kind
            case roomID = "room_id"
            case lastActiveTimestamp = "last_active_ts"
        }
    }

    /// The hours of a person's week: rows are weekdays from Monday, columns the 24 hours, in the asker's time zone.
    struct Week: Decodable, Equatable, Sendable {
        let seen: [[UInt32]]
        let onlineMilliseconds: [[UInt64]]
        let days: [UInt32]
        let firstTimestamp: UInt64?
        let lastTimestamp: UInt64?
        let entries: UInt64

        private enum CodingKeys: String, CodingKey {
            case seen, days, entries
            case onlineMilliseconds = "online_ms"
            case firstTimestamp = "first_ts"
            case lastTimestamp = "last_ts"
        }
    }

    /// Newest first.
    let chunk: [Row]
    let end: UInt64?
    let week: Week?

    private enum CodingKeys: String, CodingKey {
        case chunk, end, week
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        chunk = try container.decodeIfPresent([Row].self, forKey: .chunk) ?? []
        end = try container.decodeIfPresent(UInt64.self, forKey: .end)
        week = try container.decodeIfPresent(Week.self, forKey: .week)
    }
}

/// The room events part of a `/v3/search` response.
nonisolated struct ImxgSearchResults: Decodable, Equatable, Sendable {
    struct Result: Decodable, Equatable, Sendable {
        let rank: Double?
        let event: ImxgEvent

        private enum CodingKeys: String, CodingKey {
            case rank
            case event = "result"
        }
    }

    let count: Int?
    let highlights: [String]
    let results: [Result]
    let nextBatch: String?

    private enum OuterKeys: String, CodingKey {
        case searchCategories = "search_categories"
    }

    private enum CategoryKeys: String, CodingKey {
        case roomEvents = "room_events"
    }

    private enum CodingKeys: String, CodingKey {
        case count, highlights, results
        case nextBatch = "next_batch"
    }

    init(from decoder: Decoder) throws {
        let outer = try decoder.container(keyedBy: OuterKeys.self)
        let categories = try outer.nestedContainer(keyedBy: CategoryKeys.self, forKey: .searchCategories)
        let container = try categories.nestedContainer(keyedBy: CodingKeys.self, forKey: .roomEvents)
        count = try container.decodeIfPresent(Int.self, forKey: .count)
        highlights = try container.decodeIfPresent([String].self, forKey: .highlights) ?? []
        results = try container.decodeIfPresent([Result].self, forKey: .results) ?? []
        nextBatch = try container.decodeIfPresent(String.self, forKey: .nextBatch)
    }
}
