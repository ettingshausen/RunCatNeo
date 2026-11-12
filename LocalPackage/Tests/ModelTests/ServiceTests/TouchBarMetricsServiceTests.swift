import Foundation
import Testing

@testable import DataSource
@testable import Model

@MainActor
struct TouchBarMetricsServiceTests {
    private typealias Trigger = TouchBarMetricsService.Trigger

    private let excludedConfiguration = TouchBarConfiguration(
        mode: .smart,
        excludedBundleIdentifiers: ["com.apple.Safari"]
    )
    private let anchorOnlyConfiguration = TouchBarConfiguration(mode: .anchorOnly, excludedBundleIdentifiers: [])
    private let alwaysExpandedConfiguration = TouchBarConfiguration(mode: .alwaysExpanded, excludedBundleIdentifiers: [])

    private let safari = "com.apple.Safari"
    private let finder = "com.apple.finder"

    private func evaluate(
        _ configuration: TouchBarConfiguration,
        isEnabled: Bool = true,
        isHardwareAvailable: Bool = true,
        frontmost: String? = "com.apple.finder",
        isPresented: Bool,
        trigger: Trigger
    ) -> TouchBarMetricsService.Decision {
        TouchBarMetricsService.evaluate(
            configuration: configuration,
            isEnabled: isEnabled,
            isHardwareAvailable: isHardwareAvailable,
            frontmostBundleIdentifier: frontmost,
            isPresented: isPresented,
            trigger: trigger
        )
    }

    // MARK: smart mode

    @Test
    func smart_mode_presents_when_frontmost_app_is_not_excluded() {
        #expect(evaluate(excludedConfiguration, frontmost: finder, isPresented: false, trigger: .frontmostChanged) == .present)
    }

    @Test
    func smart_mode_minimizes_when_frontmost_app_is_excluded() {
        #expect(evaluate(excludedConfiguration, frontmost: safari, isPresented: true, trigger: .frontmostChanged) == .minimize)
    }

    @Test
    func smart_mode_keeps_presented_bar_for_non_excluded_frontmost_app() {
        #expect(evaluate(excludedConfiguration, frontmost: finder, isPresented: true, trigger: .frontmostChanged) == .none)
    }

    @Test
    func smart_mode_stays_collapsed_for_excluded_frontmost_app() {
        #expect(evaluate(excludedConfiguration, frontmost: safari, isPresented: false, trigger: .frontmostChanged) == .none)
    }

    @Test
    func smart_mode_does_nothing_without_frontmost_app() {
        #expect(evaluate(excludedConfiguration, frontmost: nil, isPresented: false, trigger: .frontmostChanged) == .none)
        #expect(evaluate(excludedConfiguration, frontmost: nil, isPresented: true, trigger: .frontmostChanged) == .none)
    }

    @Test
    func smart_mode_applies_the_mode_when_reconfigured_with_unknown_frontmost_app() {
        #expect(evaluate(excludedConfiguration, frontmost: nil, isPresented: false, trigger: .configurationChanged) == .present)
    }

    // MARK: anchor-only mode

    @Test
    func anchor_only_mode_collapses_a_presented_bar_when_the_mode_changes() {
        #expect(evaluate(anchorOnlyConfiguration, isPresented: true, trigger: .configurationChanged) == .minimize)
        #expect(evaluate(anchorOnlyConfiguration, isPresented: false, trigger: .configurationChanged) == .none)
        #expect(evaluate(anchorOnlyConfiguration, isPresented: true, trigger: .started) == .minimize)
    }

    @Test
    func anchor_only_mode_ignores_app_switches_so_a_manual_expansion_survives() {
        #expect(evaluate(anchorOnlyConfiguration, frontmost: finder, isPresented: true, trigger: .frontmostChanged) == .none)
        #expect(evaluate(anchorOnlyConfiguration, frontmost: safari, isPresented: true, trigger: .frontmostChanged) == .none)
        #expect(evaluate(anchorOnlyConfiguration, frontmost: finder, isPresented: false, trigger: .frontmostChanged) == .none)
    }

    // MARK: always-expanded mode

    @Test
    func always_expanded_mode_presents_until_presented_and_ignores_exclusions() {
        #expect(evaluate(alwaysExpandedConfiguration, frontmost: safari, isPresented: false, trigger: .frontmostChanged) == .present)
        #expect(evaluate(alwaysExpandedConfiguration, frontmost: safari, isPresented: true, trigger: .frontmostChanged) == .none)
        #expect(evaluate(alwaysExpandedConfiguration, frontmost: safari, isPresented: false, trigger: .configurationChanged) == .present)
    }

    @Test
    func always_expanded_mode_represents_after_mode_change_from_anchor_only() {
        #expect(evaluate(alwaysExpandedConfiguration, isPresented: false, trigger: .configurationChanged) == .present)
    }

    // MARK: switches

    @Test
    func disabled_minimizes_a_presented_bar() {
        #expect(evaluate(excludedConfiguration, isEnabled: false, isPresented: true, trigger: .configurationChanged) == .minimize)
        #expect(evaluate(excludedConfiguration, isEnabled: false, isPresented: false, trigger: .configurationChanged) == .none)
    }

    @Test
    func missing_hardware_minimizes_a_presented_bar() {
        #expect(evaluate(excludedConfiguration, isHardwareAvailable: false, isPresented: true, trigger: .started) == .minimize)
        #expect(evaluate(excludedConfiguration, isHardwareAvailable: false, isPresented: false, trigger: .started) == .none)
    }
}
