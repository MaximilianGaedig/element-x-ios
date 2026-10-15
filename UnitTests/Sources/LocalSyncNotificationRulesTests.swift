//
// Copyright 2026 Maximilian Gaedig.
//
// SPDX-License-Identifier: AGPL-3.0-only
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import Testing

struct LocalSyncNotificationRulesTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)
    
    private func post(sender: String = "@bob:s", at offset: TimeInterval = 5, noisy: Bool = true, hideQuiet: Bool = false) -> Bool {
        LocalSyncNotificationRules.shouldPost(senderID: sender, ownUserID: "@me:s", eventDate: start.addingTimeInterval(offset),
                                              startDate: start, isNoisy: noisy, hidesQuietAlerts: hideQuiet)
    }
    
    @Test
    func newMessagesFromOthersNotify() {
        #expect(post())
        #expect(post(at: -59), "A message from just before sync started still notifies.")
    }
    
    @Test
    func ownMessagesAndHistoryDoNot() {
        #expect(!post(sender: "@me:s"))
        #expect(!post(at: -61), "The first sync replays history; it must not notify.")
    }
    
    @Test
    func quietMessagesFollowTheSetting() {
        #expect(post(noisy: false))
        #expect(!post(noisy: false, hideQuiet: true))
        #expect(post(noisy: true, hideQuiet: true))
    }
}
