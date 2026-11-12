import Foundation
import Testing

@testable import DataSource

struct TouchBarConfigurationTests {
    @Test
    func decode_defaults_missing_keys_to_smart_mode_with_empty_exclusions() throws {
        let json = """
        {}
        """
        let configuration = try JSONDecoder().decode(TouchBarConfiguration.self, from: Data(json.utf8))
        #expect(configuration == TouchBarConfiguration.default)
        #expect(configuration.mode == .smart)
        #expect(configuration.excludedBundleIdentifiers.isEmpty)
    }

    @Test
    func encode_decode_roundtrips_mode_and_exclusions() throws {
        let configuration = TouchBarConfiguration(
            mode: .anchorOnly,
            excludedBundleIdentifiers: ["com.apple.Safari", "com.jetbrains.intellij"]
        )
        let data = try JSONEncoder().encode(configuration)
        #expect(try JSONDecoder().decode(TouchBarConfiguration.self, from: data) == configuration)
    }

    @Test
    func decode_legacy_payload_without_exclusions_yields_empty_list() throws {
        let json = """
        {"mode":"alwaysExpanded"}
        """
        let configuration = try JSONDecoder().decode(TouchBarConfiguration.self, from: Data(json.utf8))
        #expect(configuration.mode == .alwaysExpanded)
        #expect(configuration.excludedBundleIdentifiers.isEmpty)
    }

    @Test
    func decode_legacy_payload_without_visibility_shows_every_metric() throws {
        // Configurations written before per-metric visibility existed must
        // keep showing everything rather than silently going empty.
        let json = """
        {"mode":"smart","excludedBundleIdentifiers":["com.apple.Safari"]}
        """
        let configuration = try JSONDecoder().decode(TouchBarConfiguration.self, from: Data(json.utf8))
        #expect(configuration.visibleMetrics == Set(TouchBarMetric.allCases))
        #expect(configuration.shows(.cpu))
        #expect(configuration.visibleCustomMetricsSourceIDs.isEmpty)
    }

    @Test
    func encode_decode_roundtrips_visibility_selection() throws {
        let configuration = TouchBarConfiguration(
            mode: .smart,
            excludedBundleIdentifiers: [],
            visibleMetrics: [.cpu, .aiTokenUsage],
            visibleCustomMetricsSourceIDs: [UUID(1)]
        )
        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(TouchBarConfiguration.self, from: data)
        #expect(decoded == configuration)
        #expect(decoded.shows(.cpu))
        #expect(!decoded.shows(.memory))
        #expect(decoded.showsCustomMetrics(of: UUID(1)))
    }

    @Test
    func display_mode_raw_values_are_stable() {
        #expect(TouchBarDisplayMode.anchorOnly.rawValue == "anchorOnly")
        #expect(TouchBarDisplayMode.alwaysExpanded.rawValue == "alwaysExpanded")
        #expect(TouchBarDisplayMode.smart.rawValue == "smart")
        #expect(TouchBarDisplayMode.allCases.count == 3)
    }
}
