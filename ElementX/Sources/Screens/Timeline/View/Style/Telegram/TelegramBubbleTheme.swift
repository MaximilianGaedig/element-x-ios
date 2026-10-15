//
// Copyright 2013-2026 Telegram FZ-LLC and the Telegram-iOS contributors (https://github.com/TelegramMessenger/Telegram-iOS).
// Copyright 2026 Maximilian Gaedig (SwiftUI port).
//
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Values from Telegram-iOS at commit 6ad963e, which is licensed GPL-2.0-or-later (https://telegram.org/apps):
// - light: the default theme, "Day Classic" (TelegramUIPreferences/Sources/PresentationThemeSettings.swift
//   `defaultSettings`), submodules/TelegramPresentationData/Sources/DefaultDayPresentationTheme.swift, `day: false`;
// - dark: the default automatic night theme, "Night", submodules/TelegramPresentationData/Sources/DefaultDarkPresentationTheme.swift;
// - layout: submodules/TelegramUI/Components/Chat/ChatMessageItemCommon/Sources/ChatMessageItemCommon.swift
//   (`ChatMessageItemLayoutConstants.compact`) and
//   submodules/TelegramUI/Components/Chat/ChatMessageDateAndStatusNode/Sources/ChatMessageDateAndStatusNode.swift.
//

import SwiftUI

/// Which bubbles the timeline draws. One switch so upstream syncs can see what the fork changes.
nonisolated enum TimelineBubbleAppearance {
    case element
    case telegram

    static let current: TimelineBubbleAppearance = .telegram
}

/// Telegram's bubble colours, as light/dark pairs over Element's Compound tokens: only the bubble fills, their outline
/// and the time and tick colours inside them change; text keeps Compound's `textPrimary` (black / white, as Telegram).
nonisolated enum TelegramBubbleTheme {
    // MARK: Fills

    /// Incoming: `#ffffff` / `#1D1D1D` at 0.9.
    static let incomingFill = Color(tgLight: UIColor(tgRGB: 0xFFFFFF), dark: UIColor(tgRGB: 0x1D1D1D, alpha: 0.9))
    /// Outgoing, light: `#e1ffc7`.
    static let outgoingFillLight = UIColor(tgRGB: 0xE1FFC7)
    /// Outgoing, dark: a gradient over the whole chat, top to bottom (PresentationThemeEssentialGraphics.swift
    /// `outgoingBubbleGradientImage`).
    static let outgoingGradientDarkColors = [UIColor(tgRGB: 0x61BCF9), UIColor(tgRGB: 0x0088FF)]
    static let outgoingFill = Color(tgLight: outgoingFillLight, dark: UIColor(tgRGB: 0x0088FF))

    /// Light: black at 0.2 (`bubbleStrokeColor` for `day == false`); dark: none.
    static let stroke = Color(tgLight: UIColor(white: 0, alpha: 0.2), dark: .clear)

    // MARK: Time and status

    /// `secondaryTextColor`: incoming `#525252` at 0.6 / white at 0.5.
    static let incomingSecondaryText = Color(tgLight: UIColor(tgRGB: 0x525252, alpha: 0.6), dark: UIColor(white: 1, alpha: 0.5))
    /// `secondaryTextColor`: outgoing `#008c09` at 0.8 / white at 0.5.
    static let outgoingSecondaryText = Color(tgLight: UIColor(tgRGB: 0x008C09, alpha: 0.8), dark: UIColor(white: 1, alpha: 0.5))
    /// `outgoingCheckColor`: `#19c700` / white.
    static let outgoingCheck = Color(tgLight: UIColor(tgRGB: 0x19C700), dark: .white)
    /// `pendingActivityColor`, for the sending clock: outgoing `#42b649` / white at 0.5.
    static let outgoingPending = Color(tgLight: UIColor(tgRGB: 0x42B649), dark: UIColor(white: 1, alpha: 0.5))
    /// `mediaDateAndStatusFillColor` and its text, for the capsule on media.
    static let mediaStatusFill = Color(uiColor: UIColor(white: 0, alpha: 0.3))
    static let mediaStatusText = Color.white

    // MARK: Layout

    /// `text.bubbleInsets` (6 + 1 px, 11, 6 - 1 px, 11).
    static let textInsets = EdgeInsets(top: 6, leading: 11, bottom: 6, trailing: 11)
    /// `bubble.edgeInset`: from the screen edge to the bubble image (body plus tail).
    static let edgeInset: CGFloat = 3
    /// The date is 11/17 of the 17 pt base font.
    static let dateFontSize: CGFloat = 11
    /// The status area after the date: 13/17 of the base font, 5 pt after the date.
    static let statusWidth: CGFloat = 13
    static let statusSpacing: CGFloat = 5

    static func secondaryText(isOutgoing: Bool) -> Color {
        isOutgoing ? outgoingSecondaryText : incomingSecondaryText
    }
}

private nonisolated extension UIColor {
    convenience init(tgRGB rgb: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: alpha)
    }
}

private nonisolated extension Color {
    init(tgLight light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}
