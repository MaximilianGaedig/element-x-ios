//
// Copyright 2013-2026 Telegram FZ-LLC and the Telegram-iOS contributors (https://github.com/TelegramMessenger/Telegram-iOS).
// Copyright 2026 Maximilian Gaedig (SwiftUI/UIKit port).
//
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ported from Telegram-iOS at commit 6ad963e, which is licensed GPL-2.0-or-later (https://telegram.org/apps):
// - submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerImpl.swift (the blurred, dimmed
//   background: contextMenu.dimColor, Day 0x000a26 at 0.2, Night black at 0.6, over a light/dark blur);
// - ContextControllerExtractedPresentationNode.swift (the message stays above the actions with `contentActionsSpacing`
//   7, the reactions 18 above the message, 6 pt from the screen edges);
// - ContextControllerActionsStackNode.swift (actions 220-240 pt wide in a glass panel with radius min(30, h / 2),
//   10 pt above and below the rows, rows 17 pt text with 11 pt vertical and 18 pt side insets, the icon in a 32 pt slot
//   20 pt from the edge and the title at 60, separators inset 18, highlight radius min(20, h / 2));
// - submodules/ReactionSelectionNode/Sources/ReactionContextNode.swift (the reactions capsule 46 pt high, 36 pt items,
//   8 pt apart, 6 pt side insets).
// Telegram's extract/zoom animation and its custom blur radius are not ported: the menu fades in over a system blur.
//

import Compound
import SwiftUI
import UIKit

/// Presents Telegram's message context menu over the whole screen with a cross-fade, in place of Element's sheet.
struct TelegramContextMenuPresenter<Content: View>: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    @ViewBuilder let content: () -> Content

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        if isPresented {
            guard controller.presentedViewController == nil else {
                (controller.presentedViewController as? UIHostingController<AnyView>)?.rootView = AnyView(content())
                return
            }
            let hosting = UIHostingController(rootView: AnyView(content()))
            hosting.view.backgroundColor = .clear
            hosting.modalPresentationStyle = .overFullScreen
            hosting.modalTransitionStyle = .crossDissolve
            controller.present(hosting, animated: true)
        } else if controller.presentedViewController != nil {
            controller.dismiss(animated: true)
        }
    }
}

struct TelegramMessageContextMenu: View {
    @Environment(\.colorScheme) private var colorScheme

    let context: TimelineViewModel.Context
    let item: EventBasedTimelineItemProtocol
    let actions: TimelineItemMenuActions
    let dismiss: () -> Void

    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .heavy)

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)

            VStack(alignment: item.isOutgoing ? .trailing : .leading, spacing: 0) {
                if !actions.reactions.isEmpty {
                    reactions
                        .padding(.bottom, 18)
                }

                preview
                    .padding(.bottom, 7)

                actionsPanel
                    .padding(.horizontal, 6)
            }
            .frame(maxWidth: .infinity, alignment: item.isOutgoing ? .trailing : .leading)
        }
        .onAppear { feedbackGenerator.impactOccurred() }
    }

    // MARK: Background

    private var background: some View {
        ZStack {
            TelegramBlurView(style: colorScheme == .dark ? .dark : .light)
            Color(uiColor: colorScheme == .dark ? UIColor(white: 0, alpha: 0.6) : UIColor(red: 0, green: 10 / 255, blue: 38 / 255, alpha: 0.2))
        }
    }

    // MARK: Message

    @ViewBuilder
    private var preview: some View {
        if let viewState = context.viewState.timelineState.itemsDictionary[item.id.uniqueID] {
            RoomTimelineItemView(viewState: viewState)
                .environmentObject(context)
                .environment(\.timelineContext, nil)
                .environment(\.timelineGroupStyle, .single)
                .allowsHitTesting(false)
                .frame(maxHeight: 360)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Reactions

    private var reactions: some View {
        HStack(spacing: 8) {
            ForEach(actions.reactions, id: \.key) { reaction in
                Button {
                    dismiss()
                    context.send(viewAction: .toggleReaction(key: reaction.key, itemID: item.id))
                } label: {
                    Text(reaction.key)
                        .font(.system(size: 28))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(hasReacted(reaction.key) ? Color.compound.bgActionPrimaryRest.opacity(0.3) : .clear))
                }
                .accessibilityLabel(hasReacted(reaction.key) ? L10n.a11yRemoveReaction(reaction.key) : L10n.a11yAddReaction(reaction.key))
            }
            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    context.send(viewAction: .displayEmojiPicker(itemID: item.id))
                }
            } label: {
                CompoundIcon(\.reactionAdd, size: .medium, relativeTo: .compound.headingLG)
                    .foregroundStyle(.compound.iconSecondary)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel(L10n.actionReact)
        }
        .padding(.horizontal, 6)
        .frame(height: 46)
        .telegramMenuGlass(cornerRadius: 23)
        .padding(.horizontal, 6)
    }

    private func hasReacted(_ key: String) -> Bool {
        item.properties.reactions.first { $0.key == key }?.isHighlighted ?? false
    }

    // MARK: Actions

    private var actionsPanel: some View {
        let rows = actions.actions + actions.secondaryActions
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, action in
                if index > 0 {
                    Rectangle()
                        .fill(separatorColor)
                        .frame(height: 1 / UIScreen.main.scale)
                        .padding(.horizontal, 18)
                }
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        context.send(viewAction: .handleTimelineItemMenuAction(itemID: item.id, action: action))
                    }
                } label: {
                    TelegramContextActionRow(action: action, color: action.isDestructive ? destructiveColor : primaryColor)
                }
                .buttonStyle(TelegramContextActionButtonStyle(highlight: highlightColor))
            }
        }
        .padding(.vertical, 10)
        .frame(minWidth: 220, maxWidth: 240)
        .telegramMenuGlass(cornerRadius: 30)
    }

    private var primaryColor: Color { colorScheme == .dark ? .white : .black }
    private var destructiveColor: Color { Color(uiColor: colorScheme == .dark ? UIColor(red: 0xEB / 255, green: 0x55 / 255, blue: 0x45 / 255, alpha: 1) : UIColor(red: 1, green: 0x3B / 255, blue: 0x30 / 255, alpha: 1)) }
    private var separatorColor: Color { Color(uiColor: colorScheme == .dark ? UIColor(white: 1, alpha: 0.15) : UIColor(red: 0x3C / 255, green: 0x3C / 255, blue: 0x43 / 255, alpha: 0.2)) }
    private var highlightColor: Color { Color(uiColor: colorScheme == .dark ? UIColor(white: 1, alpha: 0.15) : UIColor(red: 0x3C / 255, green: 0x3C / 255, blue: 0x43 / 255, alpha: 0.2)) }
}

/// A row of `ContextControllerActionsStackNode`: the icon in a 32 pt slot 20 pt from the edge, the title at 60.
private struct TelegramContextActionRow: View {
    let action: TimelineItemMenuAction
    let color: Color

    var body: some View {
        action.label
            .labelStyle(TelegramContextLabelStyle(color: color))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
    }
}

private struct TelegramContextLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 0) {
            configuration.icon
                .foregroundStyle(color)
                .frame(width: 32)
                .padding(.leading, 20)
                .padding(.trailing, 8)
            configuration.title
                .font(.system(size: 17))
                .foregroundStyle(color)
                .lineLimit(1)
            Spacer(minLength: 18)
        }
        .padding(.vertical, 11)
    }
}

private struct TelegramContextActionButtonStyle: ButtonStyle {
    let highlight: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if configuration.isPressed {
                    RoundedRectangle(cornerRadius: 20).fill(highlight).padding(.horizontal, 6)
                }
            }
    }
}

/// A system blur (Telegram's ContextControllerImpl effect view).
private struct TelegramBlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        view.effect = UIBlurEffect(style: style)
    }
}

private extension View {
    /// Telegram's glass panels (`GlassBackgroundView`, UIGlassEffect on iOS 26), a material before.
    @ViewBuilder
    func telegramMenuGlass(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}
