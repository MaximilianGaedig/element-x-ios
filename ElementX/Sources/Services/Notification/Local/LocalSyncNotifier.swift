//
// Copyright 2026 Maximilian Gaedig.
//
// SPDX-License-Identifier: AGPL-3.0-only
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import MatrixRustSDK
import UserNotifications

/// System notifications from Element X's own sync, for hosts without push (Tunes: a free developer account has no
/// `aps-environment`, so there is no APNs and no notification service extension). The SDK evaluates the user's push
/// rules during sync (`Client.registerNotificationHandler`), so mute, mentions-only and keywords behave as with push;
/// the content comes from the NSE's `NotificationContentBuilder`.
///
/// Not posted: our own messages, events older than this process (the first sync replays recent history), events
/// already posted, and the room on screen while the app is active.
final nonisolated class LocalSyncNotifier: SyncNotificationListener, @unchecked Sendable {
    /// Events up to this long before the notifier started still notify (a message that arrived while sync was starting).
    static let startGrace: TimeInterval = 60

    private let userID: String
    private let userSettings: UserSettings
    private let session: Session
    private let mediaProvider: MediaProviderProtocol
    private let notificationCenter: UNUserNotificationCenter
    private let isSuppressed: @Sendable (String) async -> Bool
    private let startDate: Date

    private let lock = NSLock()
    private var postedEventIDs = Set<String>()
    private var postedOrder: [String] = []

    init(userID: String,
         userSettings: UserSettings,
         client: ClientProtocol,
         mediaProvider: MediaProviderProtocol,
         notificationCenter: UNUserNotificationCenter = .current(),
         isSuppressed: @escaping @Sendable (String) async -> Bool,
         startDate: Date = .now) {
        self.userID = userID
        self.userSettings = userSettings
        session = Session(userSettings: userSettings, client: client)
        self.mediaProvider = mediaProvider
        self.notificationCenter = notificationCenter
        self.isSuppressed = isSuppressed
        self.startDate = startDate
    }

    // MARK: SyncNotificationListener

    func onNotification(notification: NotificationItem, roomId: String) {
        let item = NotificationItemProxy(notificationItem: notification, receiverID: userID, roomID: roomId)
        guard case let .timeline(event) = item.event else {
            return // Invites: the room list shows them; Element X's push path handles them where push exists.
        }
        let eventID = event.eventId()
        let eventDate = Date(timeIntervalSince1970: TimeInterval(event.timestamp()) / 1000)
        guard LocalSyncNotificationRules.shouldPost(senderID: item.senderID, ownUserID: userID, eventDate: eventDate, startDate: startDate,
                              isNoisy: item.isNoisy, hidesQuietAlerts: userSettings.app.hideQuietNotificationAlerts),
            claim(eventID) else {
            return
        }
        Task { await post(item, eventID: eventID, roomID: roomId) }
    }

    /// Each event notifies once: sync can deliver an event again (a timeline reset, a second sync loop).
    private func claim(_ eventID: String) -> Bool {
        lock.withLock {
            guard postedEventIDs.insert(eventID).inserted else { return false }
            postedOrder.append(eventID)
            if postedOrder.count > 500 {
                postedEventIDs.remove(postedOrder.removeFirst())
            }
            return true
        }
    }

    private func post(_ item: NotificationItemProxy, eventID: String, roomID: String) async {
        // Off in the host, or the room is on screen in the foreground.
        if await isSuppressed(roomID) {
            return
        }
        let builder = NotificationContentBuilder(messageEventStringBuilder: RoomMessageEventStringBuilder(attributedStringBuilder: AttributedStringBuilder(mentionBuilder: PlainMentionBuilder()),
                                                                                                         style: .plain),
                                                 userSession: session)
        var content = UNMutableNotificationContent()
        await builder.process(notificationContent: &content, notificationItem: item, mediaProvider: mediaProvider)
        let request = UNNotificationRequest(identifier: eventID, content: content, trigger: nil)
        do {
            try await notificationCenter.add(request)
            MXLog.info("Local notification posted for \(eventID) in \(roomID)")
        } catch {
            MXLog.error("Local notification failed for \(eventID): \(error)")
        }
    }

    /// What the content builder needs from the session, as `NSEUserSession` provides it in the extension.
    private struct Session: NSEUserSessionProtocol {
        let userSettings: UserSettings
        let client: ClientProtocol

        var inviteAvatarsVisibility: InviteAvatars {
            get async { (try? await client.getInviteAvatarsDisplayPolicy()) ?? .on }
        }

        var mediaPreviewVisibility: MediaPreviews {
            get async { (try? await client.getMediaPreviewDisplayPolicy()) ?? .on }
        }

        var threadsEnabled: Bool {
            userSettings.app.threadsEnabled
        }
    }
}
