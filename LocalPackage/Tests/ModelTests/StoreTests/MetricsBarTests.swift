import AllocatedUnfairLock
import Foundation
import SystemInfoKit
import Testing

@testable import DataSource
@testable import Model

struct MetricsBarTests {
    private func makeSource(id: UUID) -> CustomMetricsSource {
        CustomMetricsSource(
            id: id,
            displayName: "Card",
            symbol: "staroflife",
            fileURL: URL(filePath: "/tmp/card.json"),
            bookmark: Data("bookmark".utf8),
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    @MainActor @Test
    func send_viewAppeared_loads_latest_metrics_and_observes_stream() async {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        appState.withLock { $0.metrics.send(Metrics.dummy(cpuRawValue: 0.1)) }
        let sut = MetricsBar(.testDependencies(appStateClient: .testDependency(appState)))
        await sut.send(.viewAppeared("MetricsBarTests"))
        #expect(sut.systemInfoBundle.cpuInfo?.percentage.value == 10.0)
        appState.withLock { $0.metrics.send(Metrics.dummy(cpuRawValue: 0.2)) }
        await waitUntil { sut.systemInfoBundle.cpuInfo?.percentage.value == 20.0 }
        #expect(sut.systemInfoBundle.cpuInfo?.percentage.value == 20.0)
        await sut.send(.viewDisappeared)
    }

    @MainActor @Test
    func send_viewAppeared_loads_latest_keyboardBatteries_and_observes_stream() async {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let infos = [BluetoothKeyboardInfo(id: "Keychron K6|ABC", name: "Keychron K6", percent: 36, status: .ok)]
        appState.withLock { $0.metrics.send(Metrics(keyboardBatteries: infos)) }
        let sut = MetricsBar(.testDependencies(appStateClient: .testDependency(appState)))
        await sut.send(.viewAppeared("MetricsBarTests"))
        #expect(sut.keyboardBatteries == infos)
        let updated = [BluetoothKeyboardInfo(id: "Keychron K6|ABC", name: "Keychron K6", percent: 35, status: .ok)]
        appState.withLock { $0.metrics.send(Metrics(keyboardBatteries: updated)) }
        await waitUntil { sut.keyboardBatteries == updated }
        await sut.send(.viewDisappeared)
    }

    @MainActor @Test
    func send_viewAppeared_loads_latest_fanInfo_and_observes_stream() async {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        appState.withLock { $0.metrics.send(Metrics(fanInfo: FanInfo(fans: [FanInfo.Fan(rpm: 1218)]))) }
        let sut = MetricsBar(.testDependencies(appStateClient: .testDependency(appState)))
        await sut.send(.viewAppeared("MetricsBarTests"))
        #expect(sut.fanInfo == FanInfo(fans: [FanInfo.Fan(rpm: 1218)]))
        appState.withLock { $0.metrics.send(Metrics(fanInfo: FanInfo(fans: [FanInfo.Fan(rpm: 1199)]))) }
        await waitUntil { sut.fanInfo == FanInfo(fans: [FanInfo.Fan(rpm: 1199)]) }
        await sut.send(.viewDisappeared)
    }

    @MainActor @Test
    func send_viewAppeared_refreshes_configuration_when_change_event_is_emitted() async throws {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let configurationData = AllocatedUnfairLock<Data?>(initialState: nil)
        let sut = MetricsBar(.testDependencies(
            appStateClient: .testDependency(appState),
            userDefaultsClient: testDependency(of: UserDefaultsClient.self) {
                $0.data = { _ in configurationData.withLock(\.self) }
            }
        ))
        await sut.send(.viewAppeared("MetricsBarTests"))
        #expect(sut.metricsBarConfiguration == .default)
        let updatedConfiguration = MetricsBarConfiguration(
            showsCPU: true,
            showsMemory: true,
            showsStorage: true,
            showsBattery: false,
            showsNetwork: false,
            visibleCustomMetricsSourceIDs: []
        )
        let encodedConfiguration = try JSONEncoder().encode(updatedConfiguration)
        configurationData.withLock { $0 = encodedConfiguration }
        appState.withLock { $0.systemMetricsConfigurationChanges.send() }
        await waitUntil { sut.metricsBarConfiguration == updatedConfiguration }
        #expect(sut.metricsBarConfiguration == updatedConfiguration)
        await sut.send(.viewDisappeared)
    }

    @MainActor @Test
    func send_viewAppeared_refreshes_visibility_when_custom_metrics_configuration_change_is_emitted() async {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        var initialMetricsBarConfiguration = MetricsBarConfiguration.default
        initialMetricsBarConfiguration.visibleCustomMetricsSourceIDs = [UUID(1)]
        let storage = UserDefaultsClient.storage(
            initialSources: [makeSource(id: UUID(1))],
            initialMetricsBarConfiguration: initialMetricsBarConfiguration
        )
        let sut = MetricsBar(.testDependencies(
            appStateClient: .testDependency(appState),
            userDefaultsClient: storage.client
        ))
        await sut.send(.viewAppeared("MetricsBarTests"))
        #expect(sut.metricsBarConfiguration.visibleCustomMetricsSourceIDs == [UUID(1)])
        let service = CustomMetricsService(.testDependencies(userDefaultsClient: storage.client))
        service.removeSource(of: UUID(1))
        appState.withLock { $0.customMetricsConfigurationChanges.send() }
        await waitUntil { sut.metricsBarConfiguration.visibleCustomMetricsSourceIDs.isEmpty }
        #expect(sut.metricsBarConfiguration.visibleCustomMetricsSourceIDs.isEmpty)
        await sut.send(.viewDisappeared)
    }

    @MainActor @Test
    func send_viewDisappeared_stops_observing_streams() async {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let sut = MetricsBar(.testDependencies(appStateClient: .testDependency(appState)))
        await sut.send(.viewAppeared("MetricsBarTests"))
        await sut.send(.viewDisappeared)
        appState.withLock { $0.metrics.send(Metrics.dummy(cpuRawValue: 0.3)) }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(sut.systemInfoBundle.cpuInfo == nil)
    }

    @MainActor @Test
    func touchBarIndicators_follow_the_touch_bar_visibility_not_the_menu_bar_one() {
        // The menu bar shows CPU only; the Touch Bar is allowed the fan only.
        let storage = UserDefaultsClient.storage(
            initialMetricsBarConfiguration: MetricsBarConfiguration(
                showsCPU: true,
                showsMemory: false,
                showsStorage: false,
                showsBattery: false,
                showsNetwork: false,
                showsFan: false,
                visibleCustomMetricsSourceIDs: []
            ),
            initialTouchBarConfiguration: TouchBarConfiguration(
                mode: .smart,
                excludedBundleIdentifiers: [],
                visibleMetrics: [.fan]
            )
        )
        let sut = MetricsBar(.testDependencies(userDefaultsClient: storage.client))
        sut.systemInfoBundle = Metrics.dummy(cpuRawValue: 0.42).systemInfoBundle
        sut.fanInfo = FanInfo(fans: [FanInfo.Fan(rpm: 1200, maximumRPM: 3000)])
        let indicators = sut.touchBarIndicators
        #expect(indicators == [TouchBarIndicator(systemIcon: "fanblades", primaryText: "1200")])
        #expect(sut.metricsBarConfiguration.showsCPU)
        #expect(!sut.metricsBarConfiguration.showsFan)
        #expect(!sut.touchBarConfiguration.shows(.cpu))
    }

    @MainActor @Test
    func touchBarIndicators_hide_a_zero_rpm_fan_and_show_a_spinning_one() {
        let storage = UserDefaultsClient.storage(initialTouchBarConfiguration: TouchBarConfiguration(
            mode: .smart,
            excludedBundleIdentifiers: [],
            visibleMetrics: [.fan]
        ))
        let sut = MetricsBar(.testDependencies(userDefaultsClient: storage.client))
        sut.fanInfo = FanInfo(fans: [FanInfo.Fan(rpm: 0, maximumRPM: 3000)])
        #expect(sut.touchBarIndicators.isEmpty)
        sut.fanInfo = FanInfo(fans: [FanInfo.Fan(rpm: 1200.4, maximumRPM: 3000)])
        #expect(sut.touchBarIndicators == [TouchBarIndicator(systemIcon: "fanblades", primaryText: "1200")])
    }
}
