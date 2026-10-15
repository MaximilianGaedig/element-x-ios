//
// Copyright 2013-2026 Telegram FZ-LLC and the Telegram-iOS contributors (https://github.com/TelegramMessenger/Telegram-iOS).
// Copyright 2026 Maximilian Gaedig (UIKit/SwiftUI port).
//
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ported from Telegram-iOS at commit 6ad963e, which is licensed GPL-2.0-or-later (https://telegram.org/apps):
// - submodules/WallpaperBackgroundNode/Sources/WallpaperBackgroundNode.swift (`WallpaperBackgroundNodeImpl` with a
//   pattern wallpaper: the gradient node, `patternImageLayer` (`EffectImageLayer`) on top with the soft-light filter at
//   the wallpaper's intensity, and for a negative intensity a black background, the gradient at |intensity| and the
//   pattern inverted: black with the pattern's shapes cut out);
// - submodules/TelegramPresentationData/Sources/DefaultDayPresentationTheme.swift (`defaultBuiltinWallpaperGradientColors`,
//   intensity 50) and DefaultDarkPresentationTheme.swift (`defaultDarkWallpaperGradientColors`, intensity -34);
// - submodules/TelegramUI/Sources/ChatControllerNode.swift (`onTransitionEventImpl`: a sent message steps the gradient
//   unless Reduce Motion is on or the energy settings turned translucency off).
// The pattern is Telegram's default `fqv01SQemVIBAAAApND8LDRUhRU.tgv` (submodules/TelegramUI/Resources), a gzipped SVG,
// rendered once at its 1440 x 2960 size into Assets.xcassets/TelegramPatternDefault (Telegram renders it at runtime
// with its own SVG renderer, aspect-filled to the screen, which `contentsGravity` does here).
//

import SwiftUI
import UIKit

extension Notification.Name {
    /// A message was sent: chat backgrounds step their gradient, as Telegram's `animateEvent` on send.
    static let telegramWallpaperAnimateEvent = Notification.Name("telegramWallpaperAnimateEvent")
}

/// Telegram's default chat background for the current appearance.
struct TelegramWallpaper: UIViewRepresentable {
    func makeUIView(context: Context) -> TelegramWallpaperView {
        TelegramWallpaperView()
    }

    func updateUIView(_ view: TelegramWallpaperView, context: Context) { }
}

final class TelegramWallpaperView: UIView {
    private nonisolated struct Wallpaper {
        let colors: [UIColor]
        /// Percent; negative inverts the pattern (dark themes).
        let intensity: Int

        static let day = Wallpaper(colors: [0xDBDDBB, 0x6BA587, 0xD5D88D, 0x88B884].map { UIColor(telegramRGB: $0) }, intensity: 50)
        static let night = Wallpaper(colors: [0x598BF6, 0x7A5EEF, 0xD67CFF, 0xF38B58].map { UIColor(telegramRGB: $0) }, intensity: -34)
    }

    private let gradientView: TelegramGradientBackgroundView
    private let patternLayer = CALayer()
    private var appliedStyle: UIUserInterfaceStyle?

    override init(frame: CGRect) {
        gradientView = TelegramGradientBackgroundView(colors: Wallpaper.day.colors)
        super.init(frame: frame)
        isUserInteractionEnabled = false
        addSubview(gradientView)
        patternLayer.contentsGravity = .resizeAspectFill
        layer.addSublayer(patternLayer)
        NotificationCenter.default.addObserver(self, selector: #selector(animateEvent), name: .telegramWallpaperAnimateEvent, object: nil)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: TelegramWallpaperView, _) in
            view.applyWallpaper()
        }
        applyWallpaper()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientView.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        patternLayer.frame = bounds
        CATransaction.commit()
    }

    /// `updatePatternPresentation` for the default pattern wallpaper of the current appearance.
    private func applyWallpaper() {
        let style = traitCollection.userInterfaceStyle
        guard style != appliedStyle else { return }
        appliedStyle = style
        let wallpaper: Wallpaper = style == .dark ? .night : .day
        let intensity = CGFloat(wallpaper.intensity) / 100.0

        gradientView.updateColors(wallpaper.colors)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if intensity < 0 {
            // invertPattern: black behind, the gradient at |intensity|, and a black pattern layer with the shapes cut out
            // (softlightMode .never, compositionOpacity 1).
            backgroundColor = .black
            gradientView.alpha = abs(intensity)
            patternLayer.compositingFilter = nil
            patternLayer.opacity = 1.0
            patternLayer.contents = Self.invertedPattern
        } else {
            // softlightMode .always: the black pattern at the intensity, soft-light blended over the gradient.
            backgroundColor = nil
            gradientView.alpha = 1.0
            patternLayer.compositingFilter = "softLightBlendMode"
            patternLayer.opacity = Float(intensity)
            patternLayer.contents = Self.pattern
        }
        CATransaction.commit()
    }

    @objc private func animateEvent() {
        guard !UIAccessibility.isReduceMotionEnabled, !ProcessInfo.processInfo.isLowPowerModeEnabled, window != nil else { return }
        gradientView.animateEvent()
    }

    private static let pattern: CGImage? = UIImage(named: "TelegramPatternDefault", in: .elementXResources, with: nil)?.cgImage

    /// The pattern as Telegram draws it for a negative intensity: black filled, the shapes cleared.
    private static let invertedPattern: CGImage? = {
        guard let pattern else { return nil }
        let size = CGSize(width: pattern.width, height: pattern.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor.black.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            cg.setBlendMode(.destinationOut)
            // UIKit's context is flipped relative to CGImage drawing.
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: 1, y: -1)
            cg.draw(pattern, in: CGRect(origin: .zero, size: size))
        }.cgImage
    }()
}

private nonisolated extension UIColor {
    convenience init(telegramRGB rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
