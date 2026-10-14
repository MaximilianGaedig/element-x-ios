//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

/// Element X's scenes. The app's `@main` (`Application`, used by the Xcode project and the xtool standalone build)
/// is only this scene plus the app delegate; hosts that show Element X inside their own window use
/// `ElementXEmbedded` instead.
public struct ElementXScene: Scene {
    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.displayScale) private var displayScale
    
    private let appCoordinator: AppCoordinatorProtocol
    
    /// The App's body is re-evaluated, so the coordinator is made once for the process.
    private static var sharedAppCoordinator: AppCoordinatorProtocol?
    
    public init(appDelegate: AppDelegate) {
        if let appCoordinator = Self.sharedAppCoordinator {
            self.appCoordinator = appCoordinator
            return
        }
        
        let appCoordinator: AppCoordinatorProtocol
        if ProcessInfo.isRunningUITests {
            appCoordinator = UITestsAppCoordinator(appDelegate: appDelegate)
        } else if ProcessInfo.isRunningUnitTests {
            appCoordinator = UnitTestsAppCoordinator(appDelegate: appDelegate)
        } else if ProcessInfo.isRunningAccessibilityTests {
            appCoordinator = AccessibilityTestsAppCoordinator(appDelegate: appDelegate)
        } else {
            appCoordinator = AppCoordinator(appDelegate: appDelegate)
        }
        
        SceneDelegate.windowManager = appCoordinator.windowManager
        Self.sharedAppCoordinator = appCoordinator
        self.appCoordinator = appCoordinator
    }
    
    public var body: some Scene {
        WindowGroup(id: SceneDelegate.mainSceneID) {
            appCoordinator.toPresentable()
                .statusBarHidden(shouldHideStatusBar)
                .overlay(alignment: .top) {
                    if #available(iOS 26, *), ProcessInfo.processInfo.isiOSAppOnMac {
                        // Fake an old-school titlebar to reduce the "floaty-ness" of everything with liquid glass.
                        Divider().ignoresSafeArea()
                    }
                }
                .environment(\.openURL, urlRouter.action(windowType: nil))
                .onOpenURL { url in
                    urlRouter.open(url, isExternalURL: true)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                    // Universal Links opened from the Camera app's QR scanner (and NFC tags) are
                    // delivered as a browsing-web user activity rather than through `onOpenURL` 🤷‍♂️
                    guard let url = userActivity.webpageURL else { return }
                    urlRouter.open(url, isExternalURL: true)
                }
                .onContinueUserActivity("INStartCallIntent") { userActivity in
                    appCoordinator.handleUserActivity(userActivity)
                }
                .task {
                    UserAgentBuilder.displayScale = displayScale
                    appCoordinator.start()
                    appCoordinator.windowManager.configure(withOpenWindowAction: openWindow,
                                                           dismissWindowAction: dismissWindow)
                }
        }
        .handlesExternalEvents(matching: ["*"])
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L10n.actionStartChat) { }
                    .disabled(true)
            }
            
            CommandGroup(replacing: .appSettings) {
                Button(L10n.commonSettings) {
                    appCoordinator.handleAppRoute(.settings, windowType: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            
            CommandGroup(after: .windowArrangement) {
                Button("Global Search") {
                    appCoordinator.handleAppRoute(.search, windowType: nil)
                }
                .keyboardShortcut("k", modifiers: [.command])
            }
        }
        
        // This is invoked in response of the WindowManager receiving a register
        // coordinator request and invoking the `OpenWindowAction` with which
        // it's configured in the task above.
        WindowGroup(for: SecondaryWindowType.self) { $type in
            if let type {
                appCoordinator.windowManager.windowForType(type)
                    .environment(\.openURL, urlRouter.action(windowType: type))
            }
        }
        .defaultSize(width: ProcessInfo.processInfo.isiOSAppOnMac ? 600 : 400, height: 800)
        .windowResizability(.contentSize)
    }
    
    private var urlRouter: ElementXURLRouter {
        ElementXURLRouter(appCoordinator: appCoordinator, systemOpenURL: openURL)
    }
    
    /// Hide the status bar so it doesn't interfere with the screenshot tests
    private var shouldHideStatusBar: Bool {
        ProcessInfo.isRunningUITests
    }
}

/// Routes URLs opened in Element X: its own deep links first, then the phishing check, then the system.
/// Shared by `ElementXScene` and `ElementXEmbedded`.
struct ElementXURLRouter {
    let appCoordinator: AppCoordinatorProtocol
    let systemOpenURL: OpenURLAction
    
    func action(windowType: SecondaryWindowType?) -> OpenURLAction {
        .init { url in
            if appCoordinator.handleDeepLink(url, isExternalURL: false, windowType: windowType) {
                return .handled
            }
            
            if appCoordinator.handlePotentialPhishingAttempt(url: url, openURLAction: { url in
                open(url, isExternalURL: false)
            }) {
                return .handled
            }
            
            return .systemAction
        }
    }
    
    func open(_ url: URL, isExternalURL: Bool) {
        if !appCoordinator.handleDeepLink(url, isExternalURL: isExternalURL, windowType: nil) {
            openURLInSystemBrowser(url)
        }
    }
    
    /// https://github.com/element-hq/element-x-ios/issues/1824
    /// Avoid opening universal links in other app variants and infinite loops between them
    private func openURLInSystemBrowser(_ originalURL: URL) {
        guard var urlComponents = URLComponents(url: originalURL, resolvingAgainstBaseURL: true) else {
            systemOpenURL(originalURL)
            return
        }
        
        var queryItems = urlComponents.queryItems ?? []
        queryItems.append(.init(name: "no_universal_links", value: "true"))
        
        urlComponents.queryItems = queryItems
        
        guard let url = urlComponents.url else {
            systemOpenURL(originalURL)
            return
        }
        
        systemOpenURL(url)
    }
}
