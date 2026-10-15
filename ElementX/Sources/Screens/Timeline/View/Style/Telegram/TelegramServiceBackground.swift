//
// Copyright 2013-2026 Telegram FZ-LLC and the Telegram-iOS contributors (https://github.com/TelegramMessenger/Telegram-iOS).
// Copyright 2026 Maximilian Gaedig (UIKit/SwiftUI port).
//
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ported from Telegram-iOS at commit 6ad963e, which is licensed GPL-2.0-or-later (https://telegram.org/apps):
// - submodules/Display/Source/NavigationBackgroundView.swift (`NavigationBackgroundNode`: a colour over a
//   UIBlurEffect(.light) view whose tint subview is hidden and whose filters are cut down to gaussianBlur and
//   colorSaturate; no blur when the colour is opaque or transparency is reduced);
// - submodules/TelegramPresentationData/Sources/DefaultDayPresentationTheme.swift (`selectDateFillStaticColor`,
//   `dateFillNeedsBlur`) and the Day Classic / Night `serviceMessage` colours: date and service pills are black at
//   0.2 with white text, blurred over a pattern wallpaper with a positive intensity (Day), not over an inverted one
//   (Night);
// - submodules/TelegramUI/Components/Chat/ChatMessageItemImpl/Sources/ChatMessageDateHeader.swift (date pill 22 pt
//   high, 6 pt side inset, 13 pt medium) and ChatMessageActionBubbleContentNode.swift (service text 13 pt regular,
//   lines padded 7 pt into 22 pt rows with an 11 pt radius).
//

import SwiftUI
import UIKit

/// The pill behind Telegram's date headers and service messages.
struct TelegramServiceBackground: UIViewRepresentable {
    var cornerRadius: CGFloat
    
    func makeUIView(context: Context) -> TelegramServiceBackgroundView {
        TelegramServiceBackgroundView()
    }
    
    func updateUIView(_ view: TelegramServiceBackgroundView, context: Context) {
        view.cornerRadius = cornerRadius
    }
}

final class TelegramServiceBackgroundView: UIView {
    /// `dateFillStatic` of both default themes.
    private static let color = UIColor(white: 0, alpha: 0.2)
    
    private var effectView: UIVisualEffectView?
    var cornerRadius: CGFloat = 11 {
        didSet { setNeedsLayout() }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = Self.color
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: TelegramServiceBackgroundView, _) in
            view.updateBlur()
        }
        updateBlur()
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .circular
        clipsToBounds = true
        effectView?.frame = bounds
    }
    
    /// `dateFillNeedsBlur`: the Day wallpaper (positive intensity) is blurred under the pill, the Night one is not.
    private func updateBlur() {
        let needsBlur = traitCollection.userInterfaceStyle != .dark && !UIAccessibility.isReduceTransparencyEnabled
        if needsBlur, effectView == nil {
            let effectView = UIVisualEffectView(effect: UIBlurEffect(style: .light))
            for subview in effectView.subviews where subview.description.contains("VisualEffectSubview") {
                subview.isHidden = true
            }
            if let sublayer = effectView.layer.sublayers?.first, let filters = sublayer.filters {
                sublayer.backgroundColor = nil
                sublayer.isOpaque = false
                let allowedKeys = ["gaussianBlur", "colorSaturate"]
                sublayer.filters = filters.filter { filter in
                    guard let filter = filter as? NSObject else { return true }
                    return allowedKeys.contains(String(describing: filter))
                }
            }
            effectView.isUserInteractionEnabled = false
            insertSubview(effectView, at: 0)
            self.effectView = effectView
            setNeedsLayout()
        } else if !needsBlur, let effectView {
            effectView.removeFromSuperview()
            self.effectView = nil
        }
    }
}

extension View {
    /// A Telegram date pill: 13 pt medium white text, 6 pt side inset, 22 pt high.
    func telegramDatePill() -> some View {
        font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(TelegramServiceBackground(cornerRadius: 11))
    }
    
    /// A Telegram service message: 13 pt regular white text, centred, padded 7 pt into 22 pt rows with an 11 pt radius.
    func telegramServiceMessage() -> some View {
        font(.system(size: 13))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .frame(minHeight: 22)
            .background(TelegramServiceBackground(cornerRadius: 11))
    }
}
