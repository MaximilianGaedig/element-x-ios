//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import Synchronization

public nonisolated extension Bundle {
    /// The top-level bundle that contains the entire app.
    static var app: Bundle {
        var bundle = Bundle.main
        if bundle.bundleURL.pathExtension == "appex" {
            // Peel off two directory levels - MY_APP.app/PlugIns/MY_APP_EXTENSION.appex
            let url = bundle.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            if let otherBundle = Bundle(url: url) {
                bundle = otherBundle
            }
        }
        return bundle
    }
    
    /// The bundle with the app's compiled resources (asset catalog, localisations, sounds): the app bundle itself,
    /// or `ElementXResources.bundle` inside it when a SwiftPM host (the xtool build, Tunes) links ElementX as a library.
    static let elementXResources: Bundle = Bundle.app.url(forResource: "ElementXResources", withExtension: "bundle")
        .flatMap(Bundle.init(url:)) ?? Bundle.app
    
    // MARK: - Localisation
    
    /// Overrides `Bundle.app.preferredLocalizations` for testing translations since this is
    /// only for testing, and is changed at runtime only in tests, it's fine to keep as `nonisolated(unsafe)`
    nonisolated(unsafe) static var overrideLocalizations: [String]?
    
    private static let cachedBundles = Mutex<[String: Bundle]>([:])
    
    /// Get an lproj language bundle from the receiver bundle.
    /// - Parameter language: The language to try to load.
    /// - Returns: The lproj bundle if found otherwise nil.
    static func lprojBundle(for language: String) -> Bundle? {
        if let bundle = cachedValue(forKey: language) {
            return bundle
        }
        
        guard let lprojURL = Bundle.elementXResources.url(forResource: language, withExtension: "lproj") else {
            return nil
        }
        
        let bundle = Bundle(url: lprojURL)
        
        cacheValue(bundle, forKey: language)
        
        return bundle
    }
    
    // MARK: - Private
    
    private static func cacheValue(_ value: Bundle?, forKey key: String) {
        cachedBundles.withLock { $0[key] = value }
    }
    
    private static func cachedValue(forKey key: String) -> Bundle? {
        cachedBundles.withLock { $0[key] }
    }
}
