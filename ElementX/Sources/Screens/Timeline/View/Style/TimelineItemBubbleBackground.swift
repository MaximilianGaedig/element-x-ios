//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

extension View {
    /// - Parameters:
    ///   - isOutgoing: rounds the corners according to the side it shows on, defaults to true
    ///   - insets: defaults to what we use for file timeline items, text uses custom values
    ///   - color: self explanatory, defaults to subtle secondary
    ///   - borderColor: an optional colour for a border around the bubble
    func bubbleBackground(isOutgoing: Bool = true,
                          insets: EdgeInsets = .init(top: 8, leading: 12, bottom: 8, trailing: 12),
                          color: @autoclosure @MainActor () -> Color? = .compound.bgSubtleSecondary,
                          borderColor: @autoclosure @MainActor () -> Color? = nil) -> some View {
        modifier(TimelineItemBubbleBackgroundModifier(isOutgoing: isOutgoing,
                                                      insets: insets,
                                                      color: color(),
                                                      borderColor: borderColor()))
    }
}

private struct TimelineItemBubbleBackgroundModifier: ViewModifier {
    @Environment(\.timelineGroupStyle) private var timelineGroupStyle
    
    let isOutgoing: Bool
    let insets: EdgeInsets
    var color: Color?
    var borderColor: Color?
    
    func body(content: Content) -> some View {
        if TimelineBubbleAppearance.current == .telegram {
            telegramBody(content: content)
        } else {
            elementBody(content: content)
        }
    }
    
    /// Telegram iOS bubbles: the shape and tail from `TelegramBubbleShape`, a hairline outline in light mode, and
    /// the content clipped to the body (media keeps the corners but not the tail).
    private func telegramBody(content: Content) -> some View {
        let neighbors = TelegramBubbleNeighbors(timelineGroupStyle)
        let shape = TelegramBubbleShape(incoming: !isOutgoing, neighbors: neighbors)
        // Clipping is an offscreen pass per bubble, so only content that reaches the bubble's edge (media without
        // padding) is clipped; Telegram likewise only rounds its media nodes.
        let reachesEdge = min(insets.top, insets.leading, insets.bottom, insets.trailing) < 4
        return content
            .padding(insets)
            .clipShape(reachesEdge ? AnyShape(TelegramBubbleShape(incoming: !isOutgoing, neighbors: neighbors, drawsTail: false)) : AnyShape(Rectangle()))
            .background {
                if let color {
                    TelegramBubbleFill(shape: shape, color: color, isOutgoing: isOutgoing)
                }
            }
            .overlay {
                if let borderColor {
                    shape.stroke(borderColor)
                }
            }
    }
    
    private func elementBody(content: Content) -> some View {
        content
            .padding(insets)
            .background(color)
            .cornerRadius(12, corners: roundedCorners)
            .overlay {
                if let borderColor {
                    RoundedCornerShape(radius: 12, corners: roundedCorners)
                        .stroke(borderColor)
                }
            }
    }
    
    private var roundedCorners: UIRectCorner {
        switch timelineGroupStyle {
        case .single:
            return .allCorners
        case .first:
            if isOutgoing {
                return [.topLeft, .topRight, .bottomLeft]
            } else {
                return [.topLeft, .topRight, .bottomRight]
            }
        case .middle:
            return isOutgoing ? [.topLeft, .bottomLeft] : [.topRight, .bottomRight]
        case .last:
            if isOutgoing {
                return [.topLeft, .bottomLeft, .bottomRight]
            } else {
                return [.topRight, .bottomLeft, .bottomRight]
            }
        }
    }
}

/// A Telegram bubble's fill: the item's colour, except that the default outgoing fill becomes Telegram's (in dark
/// mode a screen-wide gradient each bubble shows its slice of, `TelegramBubbleBackdrop`), and the default incoming
/// fill Telegram's.
private struct TelegramBubbleFill: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    
    let shape: TelegramBubbleShape
    let color: Color
    let isOutgoing: Bool
    
    var body: some View {
        ZStack {
            if color == .compound._bgBubbleOutgoing {
                if colorScheme == .dark {
                    TelegramBubbleBackdrop(shape: shape, colors: TelegramBubbleTheme.outgoingGradientDarkColors)
                } else {
                    shape.fill(TelegramBubbleTheme.outgoingFill)
                }
            } else if color == .compound._bgBubbleIncoming {
                shape.fill(TelegramBubbleTheme.incomingFill)
            } else {
                shape.fill(color)
            }
            // `bubbleStrokeColor` (light only; Night has none), drawn UIScreenPixel + 0.25 wide.
            if colorScheme == .light {
                shape.stroke(TelegramBubbleTheme.stroke, lineWidth: 1 / displayScale + 0.25)
            }
        }
    }
}
