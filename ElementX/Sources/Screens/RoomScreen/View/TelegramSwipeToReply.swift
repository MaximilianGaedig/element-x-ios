//
// Copyright 2013-2026 Telegram FZ-LLC and the Telegram-iOS contributors (https://github.com/TelegramMessenger/Telegram-iOS).
// Copyright 2026 Maximilian Gaedig (SwiftUI port).
//
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ported from Telegram-iOS at commit 6ad963e, which is licensed GPL-2.0-or-later (https://telegram.org/apps):
// - submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift
//   (`swipeToReplyGesture`: drag the message to the left; it follows 1:1 up to 45 pt (incoming) / 60 pt (outgoing), then
//   rubber-bands (range 100, coefficient 0.4) to at most 180; a heavy haptic when the threshold is reached; released
//   past it, it replies; the message springs back in 0.3 s and the icon fades and shrinks to 0.2);
// - submodules/TelegramUI/Components/Chat/ChatSwipeToReplyRecognizer/Sources/ChatSwipeToReplyRecognizer.swift (only a
//   leftward, mostly horizontal drag starts it);
// - submodules/TelegramUI/Components/Chat/ChatMessageSwipeToReplyNode/Sources/ChatMessageSwipeToReplyNode.swift (a
//   33 pt circle on the date-pill material, 10 pt (outgoing) or -24 pt (incoming) after the message's trailing edge,
//   vertically centred, white icon).
// Telegram's progress ring around the icon is not ported; the reply icon is Compound's.
//

import Compound
import SwiftUI

struct TelegramSwipeToReply: ViewModifier {
    let isOutgoing: Bool
    let shouldStart: () -> Bool
    let action: () -> Void

    @State private var translation: CGFloat = 0
    @State private var isTracking = false
    @State private var playedHaptic = false

    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .heavy)

    private var swipeOffset: CGFloat { isOutgoing ? 60 : 45 }
    private var iconOffset: CGFloat { isOutgoing ? 10 : -24 }

    func body(content: Content) -> some View {
        content
            .offset(x: translation)
            .overlay(alignment: .trailing) {
                if isTracking || translation != 0 {
                    icon
                        .offset(x: translation + iconOffset + 33)
                        .opacity(isTracking ? 1 : 0)
                        .scaleEffect(isTracking ? 1 : 0.2)
                        .allowsHitTesting(false)
                }
            }
            .gesture(TelegramSwipeToReplyRecognizer { recognizer in
                handle(recognizer)
            })
    }

    private var icon: some View {
        CompoundIcon(\.reply, size: .small, relativeTo: .compound.bodyMD)
            .foregroundStyle(.white)
            .frame(width: 33, height: 33)
            .background(TelegramServiceBackground(cornerRadius: 16.5))
    }

    private func handle(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            guard shouldStart() else { return }
            isTracking = true
            playedHaptic = false
            feedbackGenerator.prepare()
        case .changed:
            guard isTracking else { return }
            let x = recognizer.translation(in: recognizer.view).x
            translation = x < 0 ? max(-180, min(0, -Self.rubberBandingOffset(offset: abs(x), bandingStart: swipeOffset))) : 0
            if abs(translation) / swipeOffset > 1 - .ulpOfOne, !playedHaptic {
                playedHaptic = true
                feedbackGenerator.impactOccurred()
            }
        default:
            guard isTracking else { return }
            let x = recognizer.translation(in: recognizer.view).x
            if recognizer.state == .ended, x < -swipeOffset {
                action()
            }
            withAnimation(.spring(duration: 0.3)) {
                translation = 0
                isTracking = false
            }
        }
    }

    private static func rubberBandingOffset(offset: CGFloat, bandingStart: CGFloat) -> CGFloat {
        let bandedOffset = offset - bandingStart
        if offset < bandingStart {
            return offset
        }
        let range: CGFloat = 100.0
        let coefficient: CGFloat = 0.4
        return bandingStart + (1.0 - (1.0 / ((bandedOffset * coefficient / range) + 1.0))) * range
    }
}

/// `ChatSwipeToReplyRecognizer` as a pan recogniser: it begins only for a leftward drag at least twice as wide as tall.
private struct TelegramSwipeToReplyRecognizer: UIGestureRecognizerRepresentable {
    var handle: (UIPanGestureRecognizer) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let gesture = UIPanGestureRecognizer()
        gesture.delegate = context.coordinator
        return gesture
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        handle(recognizer)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: gestureRecognizer.view)
            return velocity.x < 0 && abs(velocity.y) * 2 < abs(velocity.x)
        }
    }
}

extension View {
    /// Telegram's swipe-left-to-reply in Telegram mode, Element's swipe-right otherwise.
    @ViewBuilder
    func swipeToReply(isOutgoing: Bool,
                      label: @escaping () -> some View,
                      shouldStartAction: @escaping () -> Bool,
                      action: @escaping () -> Void) -> some View {
        if TimelineBubbleAppearance.current == .telegram {
            modifier(TelegramSwipeToReply(isOutgoing: isOutgoing, shouldStart: shouldStartAction, action: action))
        } else {
            swipeRightAction(label: label, shouldStartAction: shouldStartAction, action: action)
        }
    }
}
