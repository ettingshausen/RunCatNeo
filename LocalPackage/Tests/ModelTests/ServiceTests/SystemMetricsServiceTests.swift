import AllocatedUnfairLock
import Foundation
import SystemInfoKit
import Testing

@testable import DataSource
@testable import Model

struct SystemMetricsServiceTests {
    @Test
    func currentSystemInfoBundle_returns_value_from_observer() {
        let sut = SystemMetricsService(.testDependencies(
            systemInfoObserverClient: testDependency(of: SystemInfoObserverClient.self) {
                $0.currentSystemInfo = {
                    var bundle = SystemInfoBundle()
                    bundle.cpuInfo = CPUInfo(percentage: Percentage(rawValue: 0.42), system: .zero, user: .zero, idle: .zero)
                    return bundle
                }
            }
        ))
        #expect(sut.currentSystemInfoBundle.cpuInfo?.percentage.value == 42.0)
    }

    @Test
    func stopMonitoring_stops_observer() {
        let stopMonitoringCount = AllocatedUnfairLock<Int>(initialState: 0)
        let sut = SystemMetricsService(.testDependencies(
            systemInfoObserverClient: testDependency(of: SystemInfoObserverClient.self) {
                $0.stopMonitoring = {
                    stopMonitoringCount.withLock { $0 += 1 }
                }
            }
        ))
        sut.stopMonitoring()
        #expect(stopMonitoringCount.withLock(\.self) == 1)
    }

    @Test
    func startMonitoring_activates_configured_monitors_and_starts_observer() throws {
        let activationRequests = AllocatedUnfairLock<[SystemInfoType: Bool]?>(initialState: nil)
        let monitorInterval = AllocatedUnfairLock<Double?>(initialState: nil)
        let configuration = SystemMetricsConfiguration(
            monitorsMemory: true,
            monitorsStorage: false,
            monitorsBattery: true,
            monitorsNetwork: false
        )
        let configurationData = try JSONEncoder().encode(configuration)
        let sut = SystemMetricsService(.testDependencies(
            systemInfoObserverClient: testDependency(of: SystemInfoObserverClient.self) {
                $0.toggleActivation = { requests in
                    activationRequests.withLock { $0 = requests }
                }
                $0.startMonitoring = { interval in
                    monitorInterval.withLock { $0 = interval }
                }
            },
            userDefaultsClient: testDependency(of: UserDefaultsClient.self) {
                $0.integer = { _ in 3 }
                $0.data = { _ in configurationData }
            }
        ))
        sut.startMonitoring()
        #expect(activationRequests.withLock(\.self) == [
            .cpu: true,
            .memory: true,
            .storage: false,
            .battery: true,
            .network: false,
        ])
        #expect(monitorInterval.withLock(\.self) == 3.0)
    }

    @Test
    func startMonitoring_activates_all_monitors_when_no_configuration_is_stored() {
        let activationRequests = AllocatedUnfairLock<[SystemInfoType: Bool]?>(initialState: nil)
        let sut = SystemMetricsService(.testDependencies(
            systemInfoObserverClient: testDependency(of: SystemInfoObserverClient.self) {
                $0.toggleActivation = { requests in
                    activationRequests.withLock { $0 = requests }
                }
            }
        ))
        sut.startMonitoring()
        #expect(activationRequests.withLock(\.self) == [
            .cpu: true,
            .memory: true,
            .storage: true,
            .battery: true,
            .network: true,
        ])
    }

    @Test
    func toggleSystemMetricsActivation_passes_single_request_to_observer() {
        let activationRequests = AllocatedUnfairLock<[SystemInfoType: Bool]?>(initialState: nil)
        let sut = SystemMetricsService(.testDependencies(
            systemInfoObserverClient: testDependency(of: SystemInfoObserverClient.self) {
                $0.toggleActivation = { requests in
                    activationRequests.withLock { $0 = requests }
                }
            }
        ))
        sut.toggleSystemMetricsActivation(type: .network, isOn: false)
        #expect(activationRequests.withLock(\.self) == [.network: false])
    }

    @Test
    func updateMetrics_sends_metrics_with_appended_ring_buffer_values() {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let sut = SystemMetricsService(.testDependencies(appStateClient: .testDependency(appState)))
        var systemInfoBundle = SystemInfoBundle()
        systemInfoBundle.cpuInfo = CPUInfo(percentage: Percentage(rawValue: 0.5), system: .zero, user: .zero, idle: .zero)
        systemInfoBundle.memoryInfo = .zero
        sut.updateMetrics(from: systemInfoBundle)
        let metrics = appState.withLock(\.metrics.latestValue)
        #expect(metrics?.systemInfoBundle.cpuInfo?.percentage.value == 50.0)
        #expect(metrics?.cpuRingBuffer.values.last == 50.0)
        #expect(metrics?.memoryRingBuffer.values.last == 0.0)
    }

    @Test
    func updateMetrics_stores_fanInfo_from_smc_readings() throws {
        let readings: [String: SMCClient.Reading] = [
            "FNum": .init(dataType: "ui8 ", dataBytes: [1]),
            "F0Ac": .init(dataType: "flt ", dataBytes: withUnsafeBytes(of: Float(1218)) { Array($0) }),
            "F0Mx": .init(dataType: "flt ", dataBytes: withUnsafeBytes(of: Float(7199)) { Array($0) }),
        ]
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let sut = SystemMetricsService(.testDependencies(
            appStateClient: .testDependency(appState),
            smcClient: testDependency(of: SMCClient.self) {
                $0.read = { readings[$0] }
            }
        ))
        sut.updateMetrics(from: SystemInfoBundle())
        let fanInfo = try #require(appState.withLock(\.metrics.latestValue)?.fanInfo)
        #expect(fanInfo == FanInfo(fans: [FanInfo.Fan(rpm: 1218.0, maximumRPM: 7199.0)]))
    }

    @Test
    func updateMetrics_stores_multiple_fans_from_smc_readings() throws {
        let readings: [String: SMCClient.Reading] = [
            "FNum": .init(dataType: "ui8 ", dataBytes: [2]),
            "F0Ac": .init(dataType: "flt ", dataBytes: withUnsafeBytes(of: Float(1218)) { Array($0) }),
            "F0Mx": .init(dataType: "flt ", dataBytes: withUnsafeBytes(of: Float(7199)) { Array($0) }),
            "F1Ac": .init(dataType: "fpe2", dataBytes: [0x0F, 0x68]),
        ]
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let sut = SystemMetricsService(.testDependencies(
            appStateClient: .testDependency(appState),
            smcClient: testDependency(of: SMCClient.self) {
                $0.read = { readings[$0] }
            }
        ))
        sut.updateMetrics(from: SystemInfoBundle())
        let fanInfo = try #require(appState.withLock(\.metrics.latestValue)?.fanInfo)
        #expect(fanInfo == FanInfo(fans: [
            FanInfo.Fan(rpm: 1218.0, maximumRPM: 7199.0),
            FanInfo.Fan(rpm: 986.0),
        ]))
    }

    @Test
    func updateMetrics_stores_empty_fanInfo_when_no_fan_exists() {
        let readings: [String: SMCClient.Reading] = [
            "FNum": .init(dataType: "ui8 ", dataBytes: [0]),
        ]
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let sut = SystemMetricsService(.testDependencies(
            appStateClient: .testDependency(appState),
            smcClient: testDependency(of: SMCClient.self) {
                $0.read = { readings[$0] }
            }
        ))
        sut.updateMetrics(from: SystemInfoBundle())
        #expect(appState.withLock(\.metrics.latestValue)?.fanInfo == FanInfo(fans: []))
    }

    @Test
    func updateMetrics_stores_zero_rpm_when_actual_speed_is_missing() throws {
        let readings: [String: SMCClient.Reading] = [
            "FNum": .init(dataType: "ui8 ", dataBytes: [1]),
        ]
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let sut = SystemMetricsService(.testDependencies(
            appStateClient: .testDependency(appState),
            smcClient: testDependency(of: SMCClient.self) {
                $0.read = { readings[$0] }
            }
        ))
        sut.updateMetrics(from: SystemInfoBundle())
        let fanInfo = try #require(appState.withLock(\.metrics.latestValue)?.fanInfo)
        #expect(fanInfo == FanInfo(fans: [FanInfo.Fan(rpm: 0.0)]))
    }

    @Test
    func updateMetrics_keeps_fanInfo_nil_when_smc_is_unavailable() {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let sut = SystemMetricsService(.testDependencies(appStateClient: .testDependency(appState)))
        sut.updateMetrics(from: SystemInfoBundle())
        #expect(appState.withLock(\.metrics.latestValue)?.fanInfo == nil)
    }

    @Test
    func updateMetrics_drops_fanInfo_when_fan_monitoring_is_disabled() throws {
        let readings: [String: SMCClient.Reading] = [
            "FNum": .init(dataType: "ui8 ", dataBytes: [1]),
            "F0Ac": .init(dataType: "flt ", dataBytes: withUnsafeBytes(of: Float(1218)) { Array($0) }),
        ]
        let configurationData = try JSONEncoder().encode(SystemMetricsConfiguration(monitorsFan: false))
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let sut = SystemMetricsService(.testDependencies(
            appStateClient: .testDependency(appState),
            smcClient: testDependency(of: SMCClient.self) {
                $0.read = { readings[$0] }
            },
            userDefaultsClient: testDependency(of: UserDefaultsClient.self) {
                $0.data = { _ in configurationData }
            }
        ))
        sut.updateMetrics(from: SystemInfoBundle())
        #expect(appState.withLock(\.metrics.latestValue)?.fanInfo == nil)
    }

    @Test
    func updateMetrics_keeps_ring_buffers_when_info_is_missing() {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let sut = SystemMetricsService(.testDependencies(appStateClient: .testDependency(appState)))
        sut.updateMetrics(from: SystemInfoBundle())
        let metrics = appState.withLock(\.metrics.latestValue)
        #expect(metrics?.cpuRingBuffer.values == RingBuffer().values)
        #expect(metrics?.memoryRingBuffer.values == RingBuffer().values)
    }

    @Test
    func updateMetrics_accumulates_values_across_calls() {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let sut = SystemMetricsService(.testDependencies(appStateClient: .testDependency(appState)))
        var firstBundle = SystemInfoBundle()
        firstBundle.cpuInfo = CPUInfo(percentage: Percentage(rawValue: 0.1), system: .zero, user: .zero, idle: .zero)
        var secondBundle = SystemInfoBundle()
        secondBundle.cpuInfo = CPUInfo(percentage: Percentage(rawValue: 0.2), system: .zero, user: .zero, idle: .zero)
        sut.updateMetrics(from: firstBundle)
        sut.updateMetrics(from: secondBundle)
        #expect(appState.withLock(\.metrics.latestValue)?.cpuRingBuffer.values.suffix(2) == [10.0, 20.0])
    }

    @Test
    func emitConfigurationChange_sends_change_event() {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let sut = SystemMetricsService(.testDependencies(appStateClient: .testDependency(appState)))
        sut.emitConfigurationChange()
        #expect(appState.withLock(\.systemMetricsConfigurationChanges.latestValue) != nil)
    }
}
