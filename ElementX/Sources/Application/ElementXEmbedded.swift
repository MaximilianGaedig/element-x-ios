//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI
import UserNotifications

/// Element X inside another app's window (e.g. Tunes, which builds ElementX as a SwiftPM library).
///
/// Nothing runs until the host first shows `ElementXEmbedded.RootView()` or hands it a URL: no SDK, sync or logging at
/// launch, and no background tasks at all (they can only be registered during launch). The host forwards URLs with
/// `handle(_:)` and Element X's notifications with `willPresent(_:)` / `didReceive(_:)`; the notification center's
/// delegate stays the host's. The host's window is Element X's main window; its overlay (toasts) and app lock windows
/// are added to the same scene.
public enum ElementXEmbedded {
    private static var appCoordinator: AppCoordinator?
    private static let appDelegate = AppDelegate()
    private static var hasStarted = false
    
    /// Receives a copy of Element X's log lines (info and above, from any thread) for the host's own log.
    public static var log: ((String) -> Void)? {
        get { MXLog.hostSink }
        set { MXLog.hostSink = newValue }
    }
    
    /// Called once with how long creating Element X took (on the main thread, on first use), for the host's log.
    public static var didCreate: ((Duration) -> Void)?
    
    /// How long sync keeps running after Element X is hidden or the app goes to the background.
    public static var pauseDelay: Duration = .seconds(30)
    
    /// The host has no push (Tunes): new messages become local notifications from Element X's own sync, which then
    /// keeps running while the host is alive, hidden or in the background (`pauseDelay` is not used). Set before
    /// Element X is created.
    public static var postsLocalNotifications = false
    private static var isVisible = false
    private static var pauseTask: Task<Void, Never>?
    
    /// Whether Element X has been created in this process.
    public static var isRunning: Bool { appCoordinator != nil }
    
    /// Creates the app coordinator (settings, sessions) on first use.
    private static func makeAppCoordinatorIfNeeded() -> AppCoordinator {
        if let appCoordinator { return appCoordinator }
        let start = ContinuousClock.now
        defer { didCreate?(ContinuousClock.now - start) }
        _ = appDelegate.application(.shared, didFinishLaunchingWithOptions: nil)
        let hostNotificationDelegate = UNUserNotificationCenter.current().delegate
        let appCoordinator = AppCoordinator(appDelegate: appDelegate, usesBackgroundTasks: false)
        appCoordinator.postsLocalNotifications = postsLocalNotifications
        appCoordinator.isShownByHost = isVisible
        if let hostNotificationDelegate {
            UNUserNotificationCenter.current().delegate = hostNotificationDelegate
        }
        SceneDelegate.windowManager = appCoordinator.windowManager
        self.appCoordinator = appCoordinator
        observeApplicationState()
        return appCoordinator
    }
    
    // MARK: Sync while hidden
    
    /// The host app can stay alive in the background (audio), where the standalone app's own pause, at the end of
    /// a background task, may never come: sync pauses `pauseDelay` after Element X is hidden or the app leaves the
    /// foreground, and resumes when it is shown in the foreground again.
    private static func observeApplicationState() {
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.willEnterForegroundNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { updateSync() }
            }
        }
    }
    
    fileprivate static func setVisible(_ visible: Bool) {
        isVisible = visible
        appCoordinator?.isShownByHost = visible
        updateSync()
    }
    
    /// Starts Element X and its sync without showing it, so local notifications arrive before Chat is first opened
    /// (`postsLocalNotifications`). Does nothing once started.
    public static func startInBackground() {
        let appCoordinator = makeAppCoordinatorIfNeeded()
        guard !hasStarted else { return }
        hasStarted = true
        UserAgentBuilder.displayScale = UITraitCollection.current.displayScale
        appCoordinator.start()
        updateSync()
    }
    
    private static func updateSync() {
        guard let appCoordinator, hasStarted else { return }
        let active = postsLocalNotifications || (isVisible && UIApplication.shared.applicationState != .background)
        pauseTask?.cancel()
        pauseTask = nil
        if active {
            Task { await appCoordinator.resumeClientServices() }
        } else {
            pauseTask = Task {
                try? await Task.sleep(for: pauseDelay)
                guard !Task.isCancelled else { return }
                MXLog.info("Pausing sync: Element X hidden or in the background")
                await appCoordinator.pauseClientServices(isBackgroundTask: false)
            }
        }
    }
    
    /// Whether a URL is one Element X handles (matrix.to and `matrix:` permalinks, its custom routes), without
    /// starting it.
    public static func canHandle(_ url: URL) -> Bool {
        url.scheme == "matrix" || url.host == "matrix.to" || url.scheme == InfoPlistReader.main.baseBundleIdentifier
    }
    
    /// Handles one of Element X's URLs, starting Element X. Returns false for other URLs.
    @discardableResult public static func handle(_ url: URL) -> Bool {
        guard canHandle(url) else { return false }
        return makeAppCoordinatorIfNeeded().handleDeepLink(url, isExternalURL: true, windowType: nil)
    }
    
    /// Forwards the APNs token when the host registers for remote notifications.
    public static func didRegisterForRemoteNotifications(deviceToken: Data) {
        appDelegate.callbacks.send(.registeredNotifications(deviceToken: deviceToken))
    }
    
    /// Whether a notification is one of Element X's (messages, invites).
    public static func isElementXNotification(_ notification: UNNotification) -> Bool {
        let userInfo = notification.request.content.userInfo
        return userInfo[NotificationConstants.UserInfoKey.receiverIdentifier] != nil
            || userInfo[NotificationConstants.UserInfoKey.roomIdentifier] != nil
    }
    
    /// The presentation options for one of Element X's notifications while the app is in the foreground, nil for others.
    public static func willPresent(_ notification: UNNotification) async -> UNNotificationPresentationOptions? {
        guard isElementXNotification(notification),
              let notificationManager = appCoordinator?.notificationManager as? NotificationManager else { return nil }
        return await notificationManager.userNotificationCenter(.current(), willPresent: notification)
    }
    
    /// Handles a response to one of Element X's notifications (opens the room, sends an inline reply). Returns false
    /// for other notifications.
    public static func didReceive(_ response: UNNotificationResponse) async -> Bool {
        guard isElementXNotification(response.notification),
              let notificationManager = appCoordinator?.notificationManager as? NotificationManager else { return false }
        await notificationManager.userNotificationCenter(.current(), didReceive: response)
        return true
    }
    
    public struct RootView: View {
        @Environment(\.openURL) private var openURL
        @Environment(\.displayScale) private var displayScale
        
        public init() { }
        
        public var body: some View {
            let appCoordinator = ElementXEmbedded.makeAppCoordinatorIfNeeded()
            let windowManager = appCoordinator.windowManager as? WindowManager
            appCoordinator.toPresentable()
                .tint(.compound.textActionPrimary)
                .environment(\.openURL, ElementXURLRouter(appCoordinator: appCoordinator, systemOpenURL: openURL).action(windowType: nil))
                .background(WindowReader { window in windowManager?.configure(embeddedIn: window) })
                .onAppear {
                    windowManager?.setEmbeddedOverlayHidden(false)
                    ElementXEmbedded.setVisible(true)
                }
                .onDisappear {
                    windowManager?.setEmbeddedOverlayHidden(true)
                    ElementXEmbedded.setVisible(false)
                }
                .task {
                    guard !ElementXEmbedded.hasStarted else { return }
                    ElementXEmbedded.hasStarted = true
                    UserAgentBuilder.displayScale = displayScale
                    appCoordinator.start()
                    ElementXEmbedded.updateSync()
                    // Screen checks from the PC: launched with ELEMENTX_OPEN_URL=<matrix.to link>, opens that room
                    // (the route waits for the session like any deep link).
                    if let link = ProcessInfo.processInfo.environment["ELEMENTX_OPEN_URL"], let url = URL(string: link) {
                        ElementXEmbedded.handle(url)
                    }
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
