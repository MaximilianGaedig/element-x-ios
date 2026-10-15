//
// Copyright 2013-2026 Telegram FZ-LLC and the Telegram-iOS contributors (https://github.com/TelegramMessenger/Telegram-iOS).
// Copyright 2026 Maximilian Gaedig (SwiftUI port).
//
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ported from Telegram-iOS at commit 6ad963e, which is licensed GPL-2.0-or-later (https://telegram.org/apps):
// submodules/TelegramPresentationData/Sources/ChatMessageBubbleImages.swift
// (`messageBubbleArguments`, `messageBubbleImage`, `minRadiusForFullTailCorner`).
// Telegram draws a 39x33 stretchable image; this draws the same outline as a path at any size: the body is the
// rounded rect, and the tail keeps Telegram's coordinates relative to the bottom corner (the stretchable image's
// bottom-right quadrant, which never stretches).
//

import SwiftUI

/// `MessageBubbleImageNeighbors` without `.extracted` and `.side`, which the timeline does not use.
nonisolated enum TelegramBubbleNeighbors: Hashable {
    /// A lone message: all corners large, with a tail.
    case none
    /// The first (top) message of a group: the corner towards the next message is small.
    case top
    /// Between two messages of the same group.
    case both
    /// The last (bottom) message of a group: the corner towards the previous message is small, with a tail.
    case bottom

    init(_ groupStyle: TimelineGroupStyle) {
        switch groupStyle {
        case .single: self = .none
        case .first: self = .top
        case .middle: self = .both
        case .last: self = .bottom
        }
    }
}

/// The outline of a Telegram iOS message bubble. `rect` is the bubble's body; the tail is drawn outside it, at most
/// `TelegramBubbleShape.tailWidth` beyond the bottom corner on the sender's side.
nonisolated struct TelegramBubbleShape: Shape {
    /// `PresentationChatBubbleSettings.default` (TelegramUIPreferences/Sources/PresentationThemeSettings.swift).
    static let defaultMaxCornerRadius: CGFloat = 16
    static let defaultMinCornerRadius: CGFloat = 8
    /// The tail's width outside the body: Telegram's image is `fixedMainDiameter + 6` wide.
    static let tailWidth: CGFloat = 6

    private static let minRadiusForFullTailCorner: CGFloat = 14
    private static let fixedMainDiameter: CGFloat = 33

    var maxCornerRadius: CGFloat = defaultMaxCornerRadius
    var minCornerRadius: CGFloat = defaultMinCornerRadius
    var incoming: Bool
    var neighbors: TelegramBubbleNeighbors
    /// False clips content (media) to the body without the tail.
    var drawsTail = true

    /// `messageBubbleArguments`, for an outgoing bubble (the path is mirrored for incoming ones).
    var radii: (topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat, drawTail: Bool) {
        switch neighbors {
        case .none:
            (maxCornerRadius, maxCornerRadius, maxCornerRadius, maxCornerRadius, true)
        case .both:
            (maxCornerRadius, minCornerRadius, maxCornerRadius, minCornerRadius, false)
        case .bottom:
            (maxCornerRadius, minCornerRadius, maxCornerRadius, maxCornerRadius, true)
        case .top:
            (maxCornerRadius, maxCornerRadius, maxCornerRadius, minCornerRadius, false)
        }
    }

    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let radii = radii
        let limit = min(width, height) / 2
        let topLeft = min(radii.topLeft, limit)
        let topRight = min(radii.topRight, limit)
        let bottomLeft = min(radii.bottomLeft, limit)
        let bottomRight = min(radii.bottomRight, limit)

        let body = CGMutablePath()
        body.move(to: CGPoint(x: 0, y: topLeft))
        body.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: topLeft, y: 0), radius: topLeft)
        body.addLine(to: CGPoint(x: width - topRight, y: 0))
        body.addArc(tangent1End: CGPoint(x: width, y: 0), tangent2End: CGPoint(x: width, y: topRight), radius: topRight)
        body.addLine(to: CGPoint(x: width, y: height - bottomRight))
        body.addArc(tangent1End: CGPoint(x: width, y: height), tangent2End: CGPoint(x: width - bottomRight, y: height), radius: bottomRight)
        body.addLine(to: CGPoint(x: bottomLeft, y: height))
        body.addArc(tangent1End: CGPoint(x: 0, y: height), tangent2End: CGPoint(x: 0, y: height - bottomLeft), radius: bottomLeft)
        body.closeSubpath()

        var outline: CGPath = body
        if radii.drawTail, drawsTail {
            outline = body.union(tail(width: width, height: height))
        }

        var transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
        if incoming {
            transform = transform.translatedBy(x: width, y: 0).scaledBy(x: -1, y: 1)
        }
        return Path(outline.copy(using: &transform) ?? outline)
    }

    /// The tail in Telegram's 33x33 coordinates, moved to the body's bottom-right corner.
    private func tail(width: CGFloat, height: CGFloat) -> CGPath {
        let diameter = Self.fixedMainDiameter
        var offset = CGAffineTransform(translationX: width - diameter, y: height - diameter)

        let bottomEllipse = CGRect(x: 24, y: 16, width: 27, height: 17)
        let topEllipse = CGRect(x: 33, y: 14, width: 23, height: 21)

        let filled = CGMutablePath()
        if maxCornerRadius >= Self.minRadiusForFullTailCorner {
            filled.move(to: CGPoint(x: bottomEllipse.minX, y: bottomEllipse.midY), transform: offset)
            filled.addQuadCurve(to: CGPoint(x: bottomEllipse.midX, y: bottomEllipse.maxY),
                                control: CGPoint(x: bottomEllipse.minX, y: bottomEllipse.maxY), transform: offset)
            filled.addQuadCurve(to: CGPoint(x: bottomEllipse.maxX, y: bottomEllipse.midY),
                                control: CGPoint(x: bottomEllipse.maxX, y: bottomEllipse.maxY), transform: offset)
            filled.closeSubpath()
        } else {
            filled.addRect(CGRect(x: bottomEllipse.minX - 2, y: bottomEllipse.midY, width: bottomEllipse.width + 2, height: bottomEllipse.height / 2),
                           transform: offset)
        }
        let corner = CGMutablePath()
        corner.addRect(CGRect(x: diameter / 2, y: floor(diameter / 2), width: diameter / 2, height: ceil(bottomEllipse.midY) - floor(diameter / 2)),
                       transform: offset)
        let cutOut = CGPath(ellipseIn: topEllipse, transform: &offset)
        return filled.union(corner).subtracting(cutOut)
    }
}
