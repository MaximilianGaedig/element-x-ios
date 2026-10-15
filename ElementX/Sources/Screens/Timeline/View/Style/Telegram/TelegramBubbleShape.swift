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
        let start = ContinuousClock.now
        let key = TelegramBubblePathCache.Key(width: rect.width, height: rect.height, neighbors: neighbors, incoming: incoming,
                                              drawsTail: drawsTail, maxCornerRadius: maxCornerRadius, minCornerRadius: minCornerRadius)
        let outline: CGPath
        let isHit: Bool
        if let cached = TelegramBubblePathCache.shared.path(for: key) {
            outline = cached
            isHit = true
        } else {
            outline = makeOutline(width: rect.width, height: rect.height)
            TelegramBubblePathCache.shared.store(outline, for: key)
            isHit = false
        }
        TelegramBubblePathCache.shared.record(ContinuousClock.now - start, hit: isHit)
        return Path(outline).offsetBy(dx: rect.minX, dy: rect.minY)
    }
    
    /// The outline at the origin. Building it costs two CGPath boolean operations when there is a tail, so
    /// `path(in:)` caches it by size: a timeline re-renders the same bubbles at the same sizes on every update.
    private func makeOutline(width: CGFloat, height: CGFloat) -> CGPath {
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

        guard incoming else { return outline }
        var transform = CGAffineTransform(translationX: width, y: 0).scaledBy(x: -1, y: 1)
        return outline.copy(using: &transform) ?? outline
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

/// Bubble outlines by size, and how long `TelegramBubbleShape.path(in:)` takes (logged every 10 s while bubbles are
/// drawn, so a slow timeline shows whether the shapes are the cause).
nonisolated final class TelegramBubblePathCache: @unchecked Sendable {
    static let shared = TelegramBubblePathCache()
    
    struct Key: Hashable {
        let width: CGFloat
        let height: CGFloat
        let neighbors: TelegramBubbleNeighbors
        let incoming: Bool
        let drawsTail: Bool
        let maxCornerRadius: CGFloat
        let minCornerRadius: CGFloat
    }
    
    private static let capacity = 512
    private static let reportInterval: Duration = .seconds(10)
    
    private let lock = NSLock()
    private var paths: [Key: CGPath] = [:]
    private var hits = 0
    private var misses = 0
    private var hitTime: Duration = .zero
    private var missTime: Duration = .zero
    private var maxMissTime: Duration = .zero
    private var lastReport = ContinuousClock.now
    
    func path(for key: Key) -> CGPath? {
        lock.withLock { paths[key] }
    }
    
    func store(_ path: CGPath, for key: Key) {
        lock.withLock {
            if paths.count >= Self.capacity { paths.removeAll(keepingCapacity: true) }
            paths[key] = path
        }
    }
    
    func record(_ duration: Duration, hit: Bool) {
        let report: String? = lock.withLock {
            if hit {
                hits += 1
                hitTime += duration
            } else {
                misses += 1
                missTime += duration
                maxMissTime = max(maxMissTime, duration)
            }
            let now = ContinuousClock.now
            guard now - lastReport >= Self.reportInterval else { return nil }
            let line = "bubble paths: \(hits + misses) calls, \(misses) built in \(Self.ms(missTime)) ms (max \(Self.ms(maxMissTime)) ms), "
                + "\(hits) cached in \(Self.ms(hitTime)) ms over \(Self.ms(now - lastReport)) ms"
            hits = 0
            misses = 0
            hitTime = .zero
            missTime = .zero
            maxMissTime = .zero
            lastReport = now
            return line
        }
        if let report { MXLog.info(report) }
    }
    
    private static func ms(_ duration: Duration) -> String {
        let value = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        return String(format: "%.1f", value)
    }
}
