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
    /// Adds the send info (timestamp along indicators for edits and delivery/encryption issues) for the given timeline item to this view.
    func timelineItemSendInfo(timelineItem: EventBasedTimelineItemProtocol,
                              adjustedDeliveryStatus: TimelineItemDeliveryStatus?,
                              hasContentScanningFailure: Bool = false,
                              context: TimelineViewModel.Context) -> some View {
        modifier(TimelineItemSendInfoModifier(sendInfo: .init(timelineItem: timelineItem,
                                                              adjustedDeliveryStatus: adjustedDeliveryStatus,
                                                              hasContentScanningFailure: hasContentScanningFailure,
                                                              isReadByOthers: context.viewState.timelineState.isReadByOthers(timelineItem.id.uniqueID)),
                                              // A gallery announces this when entering it instead.
                                              isAccessibilityHidden: timelineItem is GalleryRoomTimelineItem,
                                              context: context))
    }
}

/// Adds the send info to a view with the correct layout.
private struct TimelineItemSendInfoModifier: ViewModifier {
    let sendInfo: TimelineItemSendInfo
    let isAccessibilityHidden: Bool
    let context: TimelineViewModel.Context
    
    var layout: AnyLayout {
        switch sendInfo.layoutType {
        case .horizontal(let spacing):
            AnyLayout(HStackLayout(alignment: .bottom, spacing: spacing))
        case .vertical(let spacing):
            AnyLayout(GridLayout(alignment: .leading, verticalSpacing: spacing))
        case .overlay, .hidden:
            AnyLayout(ZStackLayout(alignment: .bottomTrailing))
        }
    }
    
    func body(content: Content) -> some View {
        layout {
            content
            
            TimelineItemSendInfoLabel(sendInfo: sendInfo)
                .accessibilityHidden(isAccessibilityHidden)
                .contentShape(.rect)
                // Only tappable labels get the identifier, plain timestamps would be ambiguous matches.
                .accessibilityIdentifier(sendInfo.status != nil ? A11yIdentifiers.roomScreen.sendInfo : "")
                // Tap gesture to avoid the message being detected as a button by VoiceOver
                // (and the action shows a description that is already read to the user).
                .onTapGesture {
                    guard sendInfo.status != nil else { return }
                    context.send(viewAction: .itemSendInfoTapped(itemID: sendInfo.itemID))
                }
        }
    }
}

/// The label shown for a timeline item with info about it's timestamp and various other indicators.
private struct TimelineItemSendInfoLabel: View {
    let sendInfo: TimelineItemSendInfo
    
    var statusIcon: KeyPath<CompoundIcons, Image>? {
        switch sendInfo.status {
        case .sendingFailed: \.errorSolid
        case .encryptionAuthenticity(let authenticity): authenticity.icon
        case .encryptionForwarder: \.info
        case .none: nil
        }
    }
    
    var statusIconAccessibilityLabel: String? {
        switch sendInfo.status {
        case .sendingFailed: L10n.commonSendingFailed
        case .encryptionAuthenticity(let authenticity): authenticity.message
        case .encryptionForwarder(let forwarder): forwarder.message
        case .none: nil
        }
    }
    
    var body: some View {
        switch sendInfo.layoutType {
        case .overlay(capsuleStyle: true):
            content
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(TimelineBubbleAppearance.current == .telegram ? TelegramBubbleTheme.mediaStatusFill : Color.compound.bgSubtleSecondary)
                .cornerRadius(10)
                .padding(.trailing, 4)
                .padding(.bottom, 4)
        case .horizontal, .overlay(capsuleStyle: false):
            content
                .padding(.bottom, -4)
        case .vertical:
            GridRow {
                content
                    .gridColumnAlignment(.trailing)
            }
        case .hidden:
            EmptyView()
        }
    }
    
    @ViewBuilder
    var content: some View {
        if TimelineBubbleAppearance.current == .telegram {
            telegramContent
        } else {
            elementContent
        }
    }
    
    /// Telegram iOS's date and status (ChatMessageDateAndStatusNode.swift, 6ad963e): the time at 11 pt in the
    /// bubble's secondary colour, then the clock or checks for outgoing messages. Problems keep Element's icon.
    var telegramContent: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(sendInfo.localizedString)
                .font(.caption2)
                .foregroundStyle(telegramForegroundStyle)
            
            if let statusIcon {
                CompoundIcon(statusIcon, size: .xSmall, relativeTo: .caption2)
                    .foregroundStyle(sendInfo.foregroundStyle)
                    .padding(.leading, 4)
                    .accessibilityLabel(statusIconAccessibilityLabel ?? "")
                    .accessibilityHidden(statusIconAccessibilityLabel == nil)
            } else if let telegramStatus = sendInfo.telegramStatus {
                TelegramMessageStatusView(status: telegramStatus,
                                          checkColor: sendInfo.isOnMedia ? TelegramBubbleTheme.mediaStatusText : TelegramBubbleTheme.outgoingCheck,
                                          pendingColor: sendInfo.isOnMedia ? TelegramBubbleTheme.mediaStatusText : TelegramBubbleTheme.outgoingPending)
            }
        }
    }
    
    private var telegramForegroundStyle: Color {
        if sendInfo.isOnMedia {
            return TelegramBubbleTheme.mediaStatusText
        }
        return TelegramBubbleTheme.secondaryText(isOutgoing: sendInfo.isOutgoing)
    }
    
    var elementContent: some View {
        HStack(spacing: 4) {
            Text(sendInfo.localizedString)
            
            if let statusIcon {
                CompoundIcon(statusIcon, size: .xSmall, relativeTo: .compound.bodyXS)
                    .accessibilityLabel(statusIconAccessibilityLabel ?? "")
                    .accessibilityHidden(statusIconAccessibilityLabel == nil)
            }
        }
        .font(.compound.bodyXS)
        .foregroundStyle(sendInfo.foregroundStyle)
    }
}

/// All the data needed to render a timeline item's send info label.
private struct TimelineItemSendInfo {
    enum Status {
        case sendingFailed
        case encryptionAuthenticity(EncryptionAuthenticity)
        case encryptionForwarder(TimelineItemKeyForwarder)
    }
    
    /// Describes how the content and the send info should be arranged inside a bubble
    enum LayoutType {
        case horizontal(spacing: CGFloat = 4)
        case vertical(spacing: CGFloat = 4)
        case overlay(capsuleStyle: Bool)
        case hidden
    }
    
    let itemID: TimelineItemIdentifier
    let localizedString: String
    var status: Status?
    let layoutType: LayoutType
    var isOutgoing = false
    /// Telegram's clock or checks, for outgoing messages without a problem to show.
    var telegramStatus: TelegramMessageStatus?
    
    /// Drawn on a dark capsule over media, in white like Telegram's `mediaDateAndStatusTextColor`.
    var isOnMedia: Bool {
        if case .overlay(capsuleStyle: true) = layoutType { return true }
        return false
    }
    
    var foregroundStyle: Color {
        switch status {
        case .sendingFailed:
            .compound.textCriticalPrimary
        case .encryptionAuthenticity(let authenticity):
            authenticity.foregroundStyle
        case .encryptionForwarder:
            .compound.textSecondary
        case .none:
            .compound.textSecondary
        }
    }
}

private extension TimelineItemSendInfo {
    init(timelineItem: EventBasedTimelineItemProtocol,
         adjustedDeliveryStatus: TimelineItemDeliveryStatus?,
         hasContentScanningFailure: Bool = false,
         isReadByOthers: Bool = false) {
        itemID = timelineItem.id
        localizedString = timelineItem.localizedSendInfo
        isOutgoing = timelineItem.isOutgoing
        telegramStatus = if !timelineItem.isOutgoing {
            nil
        } else {
            switch adjustedDeliveryStatus {
            case .sending: .sending
            case .sendingFailed: nil
            case .sent, .none: isReadByOthers ? .read : .sent
            }
        }
        
        status = if case .sendingFailed = adjustedDeliveryStatus {
            .sendingFailed
        } else if let authenticity = timelineItem.properties.encryptionAuthenticity {
            .encryptionAuthenticity(authenticity)
        } else if let forwarder = timelineItem.properties.encryptionForwarder {
            .encryptionForwarder(forwarder)
        } else {
            nil
        }
        
        layoutType = if hasContentScanningFailure {
            // The content scanner failure placeholder replaces the media,
            // so the send info is laid out like it is for a text message.
            timelineItem.hasMediaCaption ? .overlay(capsuleStyle: false) : .horizontal()
        } else {
            switch timelineItem {
            case is TextBasedRoomTimelineItem:
                .overlay(capsuleStyle: false)
            case let liveLocationTimelineItem as LiveLocationRoomTimelineItem:
                liveLocationTimelineItem.layout
            case let message as EventBasedMessageTimelineItemProtocol:
                switch message {
                case is ImageRoomTimelineItem, is VideoRoomTimelineItem:
                    .overlay(capsuleStyle: !message.hasMediaCaption)
                case is GalleryRoomTimelineItem:
                    // Without a caption, append the send info below the grid rather than overlaying
                    // a capsule on top of the media.
                    message.hasMediaCaption ? .overlay(capsuleStyle: false) : .vertical()
                case is AudioRoomTimelineItem, is FileRoomTimelineItem:
                    // swiftlint:disable:next void_function_in_ternary
                    message.hasMediaCaption ? .overlay(capsuleStyle: false) : .horizontal(spacing: 0) // No spacing as the content already contains it.
                case let locationTimelineItem as LocationRoomTimelineItem:
                    .overlay(capsuleStyle: locationTimelineItem.content.geoURI != nil)
                default:
                    .horizontal()
                }
            case is StickerRoomTimelineItem:
                .overlay(capsuleStyle: true)
            case is PollRoomTimelineItem:
                .vertical(spacing: 16)
            default:
                .horizontal()
            }
        }
    }
}

private extension LiveLocationRoomTimelineItem {
    var layout: TimelineItemSendInfo.LayoutType {
        if content.isLive, isOutgoing {
            .hidden
        } else {
            .overlay(capsuleStyle: true)
        }
    }
}

private extension EncryptionAuthenticity {
    var foregroundStyle: SwiftUI.Color {
        switch color {
        case .red: .compound.textCriticalPrimary
        case .gray: .compound.textSecondary
        }
    }
}

private extension TimelineItemKeyForwarder {
    static var test: TimelineItemKeyForwarder {
        TimelineItemKeyForwarder(id: "@alice:matrix.org", displayName: "alice")
    }
}

// MARK: - Previews

struct TimelineItemSendInfoLabel_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        VStack(spacing: 16) {
            TimelineItemSendInfoLabel(sendInfo: .init(itemID: .randomEvent,
                                                      localizedString: "09:47 AM",
                                                      layoutType: .horizontal()))
            TimelineItemSendInfoLabel(sendInfo: .init(itemID: .randomEvent,
                                                      localizedString: "09:47 AM",
                                                      status: .sendingFailed,
                                                      layoutType: .horizontal()))
            TimelineItemSendInfoLabel(sendInfo: .init(itemID: .randomEvent,
                                                      localizedString: "09:47 AM",
                                                      status: .encryptionAuthenticity(.unsignedDevice(color: .red)),
                                                      layoutType: .horizontal()))
            TimelineItemSendInfoLabel(sendInfo: .init(itemID: .randomEvent,
                                                      localizedString: "09:47 AM",
                                                      status: .encryptionAuthenticity(.notGuaranteed(color: .gray)),
                                                      layoutType: .horizontal()))
            TimelineItemSendInfoLabel(sendInfo: .init(itemID: .randomEvent,
                                                      localizedString: "09:47 AM",
                                                      status: .encryptionAuthenticity(.sentInClear(color: .red)),
                                                      layoutType: .horizontal()))
            TimelineItemSendInfoLabel(sendInfo: .init(itemID: .randomEvent,
                                                      localizedString: "09:47 AM",
                                                      status: .encryptionForwarder(.test),
                                                      layoutType: .horizontal()))
        }
    }
}
