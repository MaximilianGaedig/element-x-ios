//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

#if ELEMENTX_STANDALONE_PACKAGE
import ElementX
#endif
import SwiftUI

/// Shared by the Xcode project and the xtool standalone package (StandaloneApp, which links this file).
@main
struct Application: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    
    var body: some Scene {
        ElementXScene(appDelegate: appDelegate)
    }
}
