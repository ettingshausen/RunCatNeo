import Foundation
import Testing

@testable import DataSource

struct SandboxPreferencesImporterTests {
    @Test
    func importableKeys_takes_owned_keys_that_the_standard_domain_lacks() {
        let container: [String: Any] = [
            String.stockConfiguration: Data("stocks".utf8),
            String.touchBarConfiguration: Data("touchbar".utf8),
            String.runnerID: "cat",
            "NSWindow Frame settings": "junk",
        ]
        let keys = SandboxPreferencesImporter.importableKeys(
            container: container,
            existingKeys: [String.runnerID]
        )
        #expect(keys == [String.stockConfiguration, String.touchBarConfiguration])
    }

    @Test
    func importableKeys_never_overwrites_a_locally_present_key() {
        let container: [String: Any] = [
            String.stockConfiguration: Data("old".utf8),
            String.stockQuotes: Data("old".utf8),
        ]
        let keys = SandboxPreferencesImporter.importableKeys(
            container: container,
            existingKeys: [String.stockConfiguration, String.stockQuotes]
        )
        #expect(keys.isEmpty)
    }

    @Test
    func importableKeys_ignores_bookkeeping_and_unknown_keys() {
        let container: [String: Any] = [
            "NSStatusItem VisibleCC Item-1": false,
            "NSWindow Frame com_apple_SwiftUI_Settings_window": "0 0 1 1",
            "SomeOtherKey": 42,
        ]
        let keys = SandboxPreferencesImporter.importableKeys(container: container, existingKeys: [])
        #expect(keys.isEmpty)
    }

    @Test
    func containerPreferencesURL_points_into_the_container() {
        let url = SandboxPreferencesImporter.containerPreferencesURL(
            bundleIdentifier: "com.kyome.Neo.RunCat",
            homeDirectory: URL(filePath: "/Users/tester")
        )
        #expect(url.path(percentEncoded: false)
            == "/Users/tester/Library/Containers/com.kyome.Neo.RunCat/Data/Library/Preferences/com.kyome.Neo.RunCat.plist")
    }

    @Test
    func ownedKeys_covers_every_configuration_this_app_persists() {
        let keys = Set(SandboxPreferencesImporter.ownedKeys)
        for key in [
            String.stockConfiguration,
            String.stockQuotes,
            String.touchBarConfiguration,
            String.aiTokenUsageConfiguration,
            String.keyboardBatteryConfiguration,
            String.metricsBarConfiguration,
            String.systemMetricsConfiguration,
            String.customMetricsConfiguration,
            String.customRunners,
            String.runnerID,
        ] {
            #expect(keys.contains(key))
        }
    }
}
