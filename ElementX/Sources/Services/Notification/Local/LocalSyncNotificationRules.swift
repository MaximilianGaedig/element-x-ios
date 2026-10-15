//
// Copyright 2026 Maximilian Gaedig.
//
// SPDX-License-Identifier: AGPL-3.0-only
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// Which sync notifications `LocalSyncNotifier` posts, without SDK objects so it can be tested.
nonisolated enum LocalSyncNotificationRules {
    /// Events up to this long before the notifier started still notify (a message that arrived while sync was starting).
    static let startGrace: TimeInterval = 60
    
    /// Not our own messages, not history the first sync replays, and not quiet ones when the user hides those.
    static func shouldPost(senderID: String, ownUserID: String, eventDate: Date, startDate: Date,
                           isNoisy: Bool, hidesQuietAlerts: Bool) -> Bool {
        guard senderID != ownUserID else { return false }
        guard eventDate >= startDate.addingTimeInterval(-startGrace) else { return false }
        if hidesQuietAlerts, !isNoisy { return false }
        return true
    }
}
