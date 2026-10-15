//
// Copyright 2013-2026 Telegram FZ-LLC and the Telegram-iOS contributors (https://github.com/TelegramMessenger/Telegram-iOS).
// Copyright 2026 Maximilian Gaedig (SwiftUI port).
//
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ported from Telegram-iOS at commit 6ad963e, which is licensed GPL-2.0-or-later (https://telegram.org/apps):
// - submodules/TelegramPresentationData/Sources/PresentationThemeEssentialGraphics.swift (`generateCheckImage`,
//   `generateClockFrameImage`, `generateClockMinImage`);
// - submodules/TelegramUI/Components/Chat/ChatMessageDateAndStatusNode/Sources/ChatMessageDateAndStatusNode.swift
//   (where the checks and the clock sit after the date).
//

import SwiftUI

/// What the ticks after an outgoing message's time say.
nonisolated enum TelegramMessageStatus: Hashable {
    /// Still in the send queue: a clock.
    case sending
    /// On the server: one check.
    case sent
    /// Someone else read it: two checks.
    case read
}

/// The clock or checks drawn after the date, in the 5 pt gap and 13 pt status area Telegram reserves.
struct TelegramMessageStatusView: View {
    /// The gap after the date plus the status area: the sent check starts inside the gap.
    static let width: CGFloat = TelegramBubbleTheme.statusSpacing + TelegramBubbleTheme.statusWidth

    let status: TelegramMessageStatus
    let checkColor: Color
    let pendingColor: Color

    /// `generateCheckImage(width: 11)`: 11 x 9.
    private static let checkSize = CGSize(width: 11, height: 9)
    /// `checkOffset`: 6/17 of the base font.
    private static let checkOffset: CGFloat = 6

    var body: some View {
        Canvas { context, _ in
            switch status {
            case .sending:
                drawClock(in: &context)
            case .sent:
                drawCheck(partial: false, at: sentOrigin, in: &context)
            case .read:
                drawCheck(partial: false, at: sentOrigin, in: &context)
                drawCheck(partial: true, at: readOrigin, in: &context)
            }
        }
        .frame(width: Self.width, height: 13)
        .accessibilityHidden(true)
    }

    /// `checkReadFrame`: the status area's trailing edge, 3 pt down.
    private var readOrigin: CGPoint {
        CGPoint(x: TelegramBubbleTheme.statusSpacing + TelegramBubbleTheme.statusWidth - Self.checkSize.width, y: 3)
    }

    /// `checkSentFrame`: `checkOffset` before the read check.
    private var sentOrigin: CGPoint {
        CGPoint(x: readOrigin.x - Self.checkOffset, y: 3)
    }

    private func drawCheck(partial: Bool, at origin: CGPoint, in context: inout GraphicsContext) {
        var path = Path()
        if partial {
            // "M0.5,7 L7,0"
            path.move(to: CGPoint(x: 0.5, y: 7))
            path.addLine(to: CGPoint(x: 7, y: 0))
        } else {
            // "M0,4 L2.95157047,6.95157047 C2.97734507,6.97734507 3.01913396,6.97734507 3.04490857,6.95157047
            //  C3.04548448,6.95099456 3.04604969,6.95040803 3.04660389,6.9498112 L9.5,0"
            path.move(to: CGPoint(x: 0, y: 4))
            path.addLine(to: CGPoint(x: 2.95157047, y: 6.95157047))
            path.addCurve(to: CGPoint(x: 3.04490857, y: 6.95157047),
                          control1: CGPoint(x: 2.97734507, y: 6.97734507),
                          control2: CGPoint(x: 3.01913396, y: 6.97734507))
            path.addCurve(to: CGPoint(x: 3.04660389, y: 6.9498112),
                          control1: CGPoint(x: 3.04548448, y: 6.95099456),
                          control2: CGPoint(x: 3.04604969, y: 6.95040803))
            path.addLine(to: CGPoint(x: 9.5, y: 0))
        }
        // The image's context is translated by (1, 1) before drawing.
        let placed = path.applying(CGAffineTransform(translationX: origin.x + 1, y: origin.y + 1))
        context.stroke(placed, with: .color(checkColor), style: StrokeStyle(lineWidth: 0.99, lineCap: .round, lineJoin: .round))
    }

    /// `clockPosition`: centred 8.5 pt after the date and 7.5 pt down; an 11 pt circle with a 1 pt line, the hour hand
    /// up and the minute hand to the right.
    private func drawClock(in context: inout GraphicsContext) {
        let size: CGFloat = 11
        let strokeWidth: CGFloat = 1
        let origin = CGPoint(x: 8.5 - size / 2, y: 7.5 - size / 2)
        let frame = CGRect(x: origin.x + strokeWidth / 2, y: origin.y + strokeWidth / 2, width: size - strokeWidth, height: size - strokeWidth)
        context.stroke(Path(ellipseIn: frame), with: .color(pendingColor), lineWidth: strokeWidth)
        let hour = CGRect(x: origin.x + (size - strokeWidth) / 2, y: origin.y + strokeWidth * 3, width: strokeWidth, height: size / 2 - strokeWidth * 3)
        let minute = CGRect(x: origin.x + (size - strokeWidth) / 2, y: origin.y + (size - strokeWidth) / 2, width: size / 2 - strokeWidth, height: strokeWidth)
        context.fill(Path(hour), with: .color(pendingColor))
        context.fill(Path(minute), with: .color(pendingColor))
    }
}
