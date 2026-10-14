//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

/// Element X inside another app's window (e.g. Tunes, which builds ElementX as a SwiftPM library).
///
/// The host calls `launch()` while it launches (background tasks must be registered before launch completes),
/// shows `ElementXEmbedded.RootView()` where the chats belong, and forwards URLs with `handle(_:)`. The host's
/// window is Element X's main window; its overlay (toasts) and app lock windows are added to the same scene.
public enum ElementXEmbedded {
    private static var appCoordinator: AppCoordinator?
    private static let appDelegate = AppDelegate()
    private static var hasStarted = false
    
    /// Creates the app coordinator (settings, sessions, background tasks). Idempotent.
    public static func launch() {
        guard appCoordinator == nil else { return }
        _ = appDelegate.application(.shared, didFinishLaunchingWithOptions: nil)
        let appCoordinator = AppCoordinator(appDelegate: appDelegate)
        SceneDelegate.windowManager = appCoordinator.windowManager
        self.appCoordinator = appCoordinator
    }
    
    /// Handles Element X's own URLs (matrix.to and `matrix:` permalinks, its custom routes). Returns false for others.
    @discardableResult public static func handle(_ url: URL) -> Bool {
        appCoordinator?.handleDeepLink(url, isExternalURL: true, windowType: nil) ?? false
    }
    
    /// Forwards the APNs token when the host registers for remote notifications.
    public static func didRegisterForRemoteNotifications(deviceToken: Data) {
        appDelegate.callbacks.send(.registeredNotifications(deviceToken: deviceToken))
    }
    
    public struct RootView: View {
        @Environment(\.openURL) private var openURL
        @Environment(\.displayScale) private var displayScale
        
        public init() { }
        
        public var body: some View {
            if let appCoordinator = ElementXEmbedded.appCoordinator {
                let windowManager = appCoordinator.windowManager as? WindowManager
                appCoordinator.toPresentable()
                    .tint(.compound.textActionPrimary)
                    .environment(\.openURL, ElementXURLRouter(appCoordinator: appCoordinator, systemOpenURL: openURL).action(windowType: nil))
                    .background(WindowReader { window in windowManager?.configure(embeddedIn: window) })
                    .onAppear { windowManager?.setEmbeddedOverlayHidden(false) }
                    .onDisappear { windowManager?.setEmbeddedOverlayHidden(true) }
                    .task {
                        guard !ElementXEmbedded.hasStarted else { return }
                        ElementXEmbedded.hasStarted = true
                        UserAgentBuilder.displayScale = displayScale
                        appCoordinator.start()
                    }
            } else {
                Text("ElementXEmbedded.launch() was not called")
            }
        }
    }
}

/// Reports the window a SwiftUI view is in.
private struct WindowReader: UIViewRepresentable {
    let onWindow: (UIWindow) -> Void
    
    func makeUIView(context: Context) -> ReaderView {
        ReaderView(onWindow: onWindow)
    }
    
    func updateUIView(_ uiView: ReaderView, context: Context) { }
    
    final class ReaderView: UIView {
        let onWindow: (UIWindow) -> Void
        
        init(onWindow: @escaping (UIWindow) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }
        
        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { onWindow(window) }
        }
    }
}
