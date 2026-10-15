//
// Copyright 2013-2026 Telegram FZ-LLC and the Telegram-iOS contributors (https://github.com/TelegramMessenger/Telegram-iOS).
// Copyright 2026 Maximilian Gaedig (UIKit/SwiftUI port).
//
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ported from Telegram-iOS at commit 6ad963e, which is licensed GPL-2.0-or-later (https://telegram.org/apps):
// - submodules/WallpaperBackgroundNode/Sources/WallpaperBackgroundNode.swift
//   (`BubbleBackgroundNodeImpl`: `contentNode` shows the shared gradient image and `update(rect:within:)` only moves
//   its `contentsRect` to the bubble's slice of the screen);
// - submodules/TelegramPresentationData/Sources/PresentationThemeEssentialGraphics.swift (`outgoingBubbleGradientImage`,
//   a 1 x 512 vertical gradient of the outgoing fill colours);
// - submodules/ChatMessageBackground/Sources/ChatMessageBackground.swift (`ChatMessageBubbleBackdrop`: the content
//   is masked by the bubble's shape, and the list calls `update(rect:within:)` as it scrolls).
//

import SwiftUI
import UIKit

extension Notification.Name {
    /// Posted by the timeline as it scrolls, as Telegram's list calls `updateAbsoluteRect` on its items: every
    /// backdrop moves its gradient slice. Nothing is redrawn.
    static let telegramBubbleBackdropsNeedUpdate = Notification.Name("telegramBubbleBackdropsNeedUpdate")
}

/// An outgoing bubble that reveals one screen-wide gradient, as Telegram's Night theme draws them: the colour depends
/// on where the bubble is on screen. All bubbles share one tiny gradient image; each shows its slice through
/// `contentsRect` and is masked by the bubble's outline.
struct TelegramBubbleBackdrop: UIViewRepresentable {
    let shape: TelegramBubbleShape
    let colors: [UIColor]

    func makeUIView(context: Context) -> TelegramBubbleBackdropView {
        TelegramBubbleBackdropView()
    }

    func updateUIView(_ view: TelegramBubbleBackdropView, context: Context) {
        view.update(shape: shape, colors: colors)
    }
}

final class TelegramBubbleBackdropView: UIView {
    private let contentLayer = CALayer()
    private let maskLayer = CAShapeLayer()
    private var shape: TelegramBubbleShape?
    private var colors: [UIColor] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        contentLayer.mask = maskLayer
        layer.addSublayer(contentLayer)
        NotificationCenter.default.addObserver(self, selector: #selector(updateSlice), name: .telegramBubbleBackdropsNeedUpdate, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(shape: TelegramBubbleShape, colors: [UIColor]) {
        let shapeChanged = self.shape.map { $0.neighbors != shape.neighbors || $0.incoming != shape.incoming } ?? true
        self.shape = shape
        if colors != self.colors {
            self.colors = colors
            contentLayer.contents = Self.gradientImage(colors: colors)
        }
        if shapeChanged { setNeedsLayout() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let shape else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The tail hangs outside the body on the sender's side.
        let tail = TelegramBubbleShape.tailWidth
        contentLayer.frame = bounds.insetBy(dx: -tail, dy: 0)
        maskLayer.frame = contentLayer.bounds
        maskLayer.path = shape.path(in: CGRect(x: tail, y: 0, width: bounds.width, height: bounds.height)).cgPath
        CATransaction.commit()
        updateSlice()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateSlice()
    }

    /// `BubbleBackgroundNodeImpl.update(rect:within:)`: the slice of the screen-wide image under this bubble.
    @objc private func updateSlice() {
        guard let window, window.bounds.width > 0, window.bounds.height > 0 else { return }
        let rect = contentLayer.convert(contentLayer.bounds, to: window.layer)
        let container = window.bounds.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.contentsRect = CGRect(x: rect.minX / container.width, y: rect.minY / container.height,
                                           width: rect.width / container.width, height: rect.height / container.height)
        CATransaction.commit()
    }

    private static var imageCache: [[UIColor]: CGImage] = [:]

    /// `outgoingBubbleGradientImage`: 1 x 512, the colours evenly spaced from top to bottom.
    private static func gradientImage(colors: [UIColor]) -> CGImage? {
        if let cached = imageCache[colors] { return cached }
        let size = CGSize(width: 1, height: 512)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cgColors = colors.map(\.cgColor) as CFArray
            var locations = colors.indices.map { CGFloat($0) / CGFloat(max(colors.count - 1, 1)) }
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: &locations) else { return }
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }.cgImage
        imageCache[colors] = image
        return image
    }
}
