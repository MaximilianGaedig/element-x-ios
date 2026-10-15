//
// Copyright 2013-2026 Telegram FZ-LLC and the Telegram-iOS contributors (https://github.com/TelegramMessenger/Telegram-iOS).
// Copyright 2026 Maximilian Gaedig (SwiftUI port).
//
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ported from Telegram-iOS at commit 6ad963e, which is licensed GPL-2.0-or-later (https://telegram.org/apps):
// - submodules/TelegramUI/Components/ChatTitleView/Sources/ChatTitleView.swift: the title (17 pt semibold) and status
//   (13 pt regular, secondary) centred in a glass capsule 44 pt high with 12 pt side padding (`backgroundFrame`,
//   `GlassBackgroundView` with the `.panel` tint), the status line under the title with no spacing;
// - submodules/TelegramUI/Components/Chat/ChatAvatarNavigationNode/Sources/ChatAvatarNavigationNode.swift: the avatar
//   as its own 44 pt glass circle on the trailing side, the image inset by 3 pt.
// On iOS 26 Telegram's GlassBackgroundView is the system UIGlassEffect, which SwiftUI's glassEffect also uses.
//

import Compound
import SwiftUI

/// Telegram's chat title capsule: name and status, centred, tapping opens the chat's details.
struct TelegramChatTitleView: View {
    let title: String
    let subtitle: String?
    let action: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                .foregroundStyle(.compound.textPrimary)
                .lineLimit(1)
                .accessibilityIdentifier(A11yIdentifiers.roomScreen.name)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.compound.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .telegramGlass(in: .capsule)
        .contentShape(.capsule)
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Telegram's trailing avatar button: the avatar inset 3 pt in a 44 pt glass circle.
struct TelegramChatAvatarButton: View {
    let avatar: RoomAvatar
    let mediaProvider: MediaProviderProtocol?
    let action: () -> Void
    
    var body: some View {
        RoomAvatarImage(avatar: avatar, avatarSize: .custom(38), mediaProvider: mediaProvider)
            .frame(width: 38, height: 38)
            .clipShape(.circle)
            .padding(3) // The toolbar item draws the glass circle around it.
            .contentShape(.circle)
            .onTapGesture(perform: action)
            .accessibilityIdentifier(A11yIdentifiers.roomScreen.avatar)
            .accessibilityAddTraits(.isButton)
    }
}

private extension View {
    /// Telegram's `GlassBackgroundView` (`UIGlassEffect`, `.regular`) on iOS 26, a material before.
    @ViewBuilder
    func telegramGlass(in shape: some Shape) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }
}
