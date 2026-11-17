/*
 SandboxPreferencesImporter.swift
 DataSource

 Created by ettingshausen on 2026/11/17.
 Copyright 2026 ettingshausen

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

import Foundation

/// Recovery for a build that accidentally shipped sandboxed: macOS moves an
/// app's preferences into its container on the first sandboxed launch, so an
/// unsandboxed launch afterwards reads an empty domain and every setting looks
/// lost. The container file itself is unreadable from a shell (TCC), but the
/// app may read its own container, so the app imports the missing keys once.
public enum SandboxPreferencesImporter {
    /// Every defaults key this app owns. Only these are imported: the
    /// container plist also holds AppKit bookkeeping such as window frames.
    public static let ownedKeys: [String] = [
        String.aiTokenUsageConfiguration,
        String.customMetricsConfiguration,
        String.customRunners,
        String.isFlippedHorizontally,
        String.keyboardBatteryConfiguration,
        String.metricsBarConfiguration,
        String.runnerID,
        String.speedDecreasesUnderLoad,
        String.stockConfiguration,
        String.stockQuotes,
        String.systemMetricsConfiguration,
        String.touchBarConfiguration,
        String.updateInterval,
        String.showsMetricsBar,
        String.showsMetricsBarOnTouchBar,
        "TouchBarOLEDProtectionPixelShiftEnabled",
        "TouchBarStockIndicatorBrightness",
        "TouchBarIndicatorBrightness",
    ]

    /// The marker key that keeps the import to a single run.
    public static let completedKey = "SANDBOX_PREFERENCES_IMPORTED"

    /// Keys to copy: owned, present in the container, and absent locally.
    /// A locally present key wins — newer settings must never be overwritten
    /// by the stale container copy.
    public static func importableKeys(
        container: [String: Any],
        existingKeys: Set<String>
    ) -> [String] {
        ownedKeys.filter { key in
            container[key] != nil && !existingKeys.contains(key)
        }
    }

    /// Reads the container plist and writes its missing owned keys into the
    /// standard domain. Lives here because `UserDefaultsClient`'s members are
    /// internal to this module. Returns the imported keys for logging.
    @discardableResult
    public static func run(
        client: UserDefaultsClient,
        bundleIdentifier: String,
        containerURL: URL
    ) -> [String] {
        guard !client.bool(completedKey) else { return [] }
        guard let data = try? Data(contentsOf: containerURL),
              let container = (try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              )) as? [String: Any] else {
            return []
        }
        let existing = Set((client.persistentDomain(bundleIdentifier) ?? [:]).keys)
        let keys = importableKeys(container: container, existingKeys: existing)
        for key in keys {
            client.set(container[key], key)
        }
        client.set(true, completedKey)
        return keys
    }

    /// The container preference file a sandboxed launch would have used.
    public static func containerPreferencesURL(
        bundleIdentifier: String,
        homeDirectory: URL
    ) -> URL {
        homeDirectory.appending(
            path: "Library/Containers/\(bundleIdentifier)/Data/Library/Preferences/\(bundleIdentifier).plist"
        )
    }
}
