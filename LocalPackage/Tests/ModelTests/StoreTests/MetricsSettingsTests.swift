import AllocatedUnfairLock
import Foundation
import SystemInfoKit
import Testing

@testable import DataSource
@testable import Model

struct MetricsSettingsTests {
    @MainActor @Test
    func send_viewAppeared_refreshes_configuration_when_change_event_is_emitted() async throws {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let storage = UserDefaultsClient.storage()
        let sut = MetricsSettings(.testDependencies(
            appStateClient: .testDependency(appState),
            userDefaultsClient: storage.client
        ))
        await sut.send(.viewAppeared("MetricsSettingsTests"))
        #expect(sut.systemMetricsConfiguration == .default)
        let updatedConfiguration = SystemMetricsConfiguration(
            monitorsMemory: false,
            monitorsStorage: false,
            monitorsBattery: false,
            monitorsNetwork: false
        )
        let encodedConfiguration = try JSONEncoder().encode(updatedConfiguration)
        storage.lock.withLock { $0[.systemMetricsConfiguration] = encodedConfiguration }
        appState.withLock { $0.systemMetricsConfigurationChanges.send() }
        await waitUntil { sut.systemMetricsConfiguration == updatedConfiguration }
        #expect(sut.systemMetricsConfiguration == updatedConfiguration)
        await sut.send(.viewDisappeared)
    }

    @MainActor @Test
    func send_viewDisappeared_stops_observing_configuration_changes() async throws {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let storage = UserDefaultsClient.storage()
        let sut = MetricsSettings(.testDependencies(
            appStateClient: .testDependency(appState),
            userDefaultsClient: storage.client
        ))
        await sut.send(.viewAppeared("MetricsSettingsTests"))
        await sut.send(.viewDisappeared)
        let updatedConfiguration = SystemMetricsConfiguration(
            monitorsMemory: false,
            monitorsStorage: false,
            monitorsBattery: false,
            monitorsNetwork: false
        )
        let encodedConfiguration = try JSONEncoder().encode(updatedConfiguration)
        storage.lock.withLock { $0[.systemMetricsConfiguration] = encodedConfiguration }
        appState.withLock { $0.systemMetricsConfigurationChanges.send() }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(sut.systemMetricsConfiguration == .default)
    }

    @MainActor @Test
    func send_showMetricsBarToggleSwitched_on_shows_notes_sheet_without_persisting() async {
        let setCallStack = AllocatedUnfairLock<[String]>(initialState: [])
        let sut = MetricsSettings(.testDependencies(
            userDefaultsClient: testDependency(of: UserDefaultsClient.self) {
                $0.set = { value, key in
                    let entry = "set: \(key) = \(value ?? "nil")"
                    setCallStack.withLock { $0.append(entry) }
                }
            }
        ))
        await sut.send(.showMetricsBarToggleSwitched(true))
        #expect(sut.showingMetricsBarNotesSheet)
        #expect(!sut.showsMetricsBar)
        #expect(setCallStack.withLock(\.self).isEmpty)
    }

    @MainActor @Test
    func send_showMetricsBarToggleSwitched_off_persists_flag() async {
        let setCallStack = AllocatedUnfairLock<[String]>(initialState: [])
        let sut = MetricsSettings(.testDependencies(
            userDefaultsClient: testDependency(of: UserDefaultsClient.self) {
                $0.set = { value, key in
                    let entry = "set: \(key) = \(value ?? "nil")"
                    setCallStack.withLock { $0.append(entry) }
                }
            }
        ), showsMetricsBar: true)
        await sut.send(.showMetricsBarToggleSwitched(false))
        #expect(!sut.showingMetricsBarNotesSheet)
        #expect(!sut.showsMetricsBar)
        #expect(setCallStack.withLock(\.self) == ["set: SHOWS_METRICS_BAR = false"])
    }

    @MainActor @Test
    func send_changedMyMindButtonTapped_dismisses_sheet_without_enabling() async {
        let setCallStack = AllocatedUnfairLock<[String]>(initialState: [])
        let sut = MetricsSettings(.testDependencies(
            userDefaultsClient: testDependency(of: UserDefaultsClient.self) {
                $0.set = { value, key in
                    let entry = "set: \(key) = \(value ?? "nil")"
                    setCallStack.withLock { $0.append(entry) }
                }
            }
        ), showingMetricsBarNotesSheet: true)
        await sut.send(.changedMyMindButtonTapped)
        #expect(!sut.showingMetricsBarNotesSheet)
        #expect(!sut.showsMetricsBar)
        #expect(setCallStack.withLock(\.self).isEmpty)
    }

    @MainActor @Test
    func send_showsMetricsBarOnTouchBarToggleSwitched_persists_flag_and_emits_change() async {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let setCallStack = AllocatedUnfairLock<[String]>(initialState: [])
        let sut = MetricsSettings(.testDependencies(
            appStateClient: .testDependency(appState),
            userDefaultsClient: testDependency(of: UserDefaultsClient.self) {
                $0.set = { value, key in
                    let entry = "set: \(key) = \(value ?? "nil")"
                    setCallStack.withLock { $0.append(entry) }
                }
            }
        ))
        #expect(appState.withLock(\.touchBarConfigurationChanges.latestValue) == nil)
        await sut.send(.showsMetricsBarOnTouchBarToggleSwitched(true))
        #expect(sut.showsMetricsBarOnTouchBar)
        #expect(setCallStack.withLock(\.self) == ["set: SHOWS_METRICS_BAR_ON_TOUCH_BAR = true"])
        #expect(appState.withLock(\.touchBarConfigurationChanges.latestValue) != nil)
    }

    @MainActor @Test
    func send_touchBarDisplayModeSelected_persists_configuration_and_emits_change() async throws {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let storage = UserDefaultsClient.storage()
        let sut = MetricsSettings(.testDependencies(
            appStateClient: .testDependency(appState),
            userDefaultsClient: storage.client
        ))
        await sut.send(.touchBarDisplayModeSelected(.anchorOnly))
        #expect(sut.touchBarConfiguration.mode == .anchorOnly)
        let saved = storage.lock.withLock { $0[.touchBarConfiguration] }
            .flatMap { try? JSONDecoder().decode(TouchBarConfiguration.self, from: $0) }
        #expect(saved?.mode == .anchorOnly)
        #expect(appState.withLock(\.touchBarConfigurationChanges.latestValue) != nil)
    }

    @MainActor @Test
    func send_touchBarExcludeCurrentAppButtonTapped_appends_frontmost_app_once() async throws {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let storage = UserDefaultsClient.storage()
        let sut = MetricsSettings(.testDependencies(
            appStateClient: .testDependency(appState),
            nsWorkspaceClient: testDependency(of: NSWorkspaceClient.self) {
                $0.frontmostApplication = {
                    FrontmostApplicationInfo(bundleIdentifier: "com.apple.Safari", localizedName: "Safari")
                }
            },
            userDefaultsClient: storage.client
        ))
        await sut.send(.touchBarExcludeCurrentAppButtonTapped)
        #expect(sut.touchBarConfiguration.excludedBundleIdentifiers == ["com.apple.Safari"])
        await sut.send(.touchBarExcludeCurrentAppButtonTapped)
        #expect(sut.touchBarConfiguration.excludedBundleIdentifiers == ["com.apple.Safari"])
        let saved = storage.lock.withLock { $0[.touchBarConfiguration] }
            .flatMap { try? JSONDecoder().decode(TouchBarConfiguration.self, from: $0) }
        #expect(saved?.excludedBundleIdentifiers == ["com.apple.Safari"])
    }

    @MainActor @Test
    func send_touchBarExcludeCurrentAppButtonTapped_uses_the_last_external_frontmost_app() async throws {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let storage = UserDefaultsClient.storage()
        appState.withLock {
            $0.lastExternalFrontmostApplication = FrontmostApplicationInfo(
                bundleIdentifier: "com.apple.Safari",
                localizedName: "Safari"
            )
        }
        let sut = MetricsSettings(.testDependencies(
            appStateClient: .testDependency(appState),
            nsWorkspaceClient: testDependency(of: NSWorkspaceClient.self) {
                // Clicking the button makes this app frontmost; the remembered
                // app must win over the live frontmost application.
                $0.frontmostApplication = {
                    FrontmostApplicationInfo(bundleIdentifier: Bundle.main.bundleIdentifier ?? "", localizedName: "Self")
                }
            },
            userDefaultsClient: storage.client
        ))
        await sut.send(.touchBarExcludeCurrentAppButtonTapped)
        #expect(sut.touchBarConfiguration.excludedBundleIdentifiers == ["com.apple.Safari"])
    }

    @MainActor @Test
    func send_touchBarAppsImported_adds_resolved_bundle_identifiers_without_duplicates() async throws {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let storage = UserDefaultsClient.storage(initialTouchBarConfiguration: TouchBarConfiguration(
            mode: .smart,
            excludedBundleIdentifiers: ["com.apple.Safari"]
        ))
        let sut = MetricsSettings(.testDependencies(
            appStateClient: .testDependency(appState),
            nsWorkspaceClient: testDependency(of: NSWorkspaceClient.self) {
                $0.bundleIdentifier = { url in
                    url.lastPathComponent == "Safari.app" ? "com.apple.Safari" : "com.jetbrains.intellij"
                }
            },
            userDefaultsClient: storage.client
        ))
        await sut.send(.touchBarAppsImported([
            URL(fileURLWithPath: "/Applications/Safari.app"),
            URL(fileURLWithPath: "/Applications/IntelliJ IDEA.app"),
        ]))
        #expect(sut.touchBarConfiguration.excludedBundleIdentifiers == ["com.apple.Safari", "com.jetbrains.intellij"])
        let saved = storage.lock.withLock { $0[.touchBarConfiguration] }
            .flatMap { try? JSONDecoder().decode(TouchBarConfiguration.self, from: $0) }
        #expect(saved?.excludedBundleIdentifiers == ["com.apple.Safari", "com.jetbrains.intellij"])
    }

    @MainActor @Test
    func send_touchBarExcludedAppRemoved_removes_only_the_given_identifier() async throws {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let storage = UserDefaultsClient.storage(initialTouchBarConfiguration: TouchBarConfiguration(
            mode: .smart,
            excludedBundleIdentifiers: ["com.apple.Safari", "com.jetbrains.intellij"]
        ))
        let sut = MetricsSettings(.testDependencies(
            appStateClient: .testDependency(appState),
            userDefaultsClient: storage.client
        ))
        await sut.send(.touchBarExcludedAppRemoved("com.apple.Safari"))
        #expect(sut.touchBarConfiguration.excludedBundleIdentifiers == ["com.jetbrains.intellij"])
        let saved = storage.lock.withLock { $0[.touchBarConfiguration] }
            .flatMap { try? JSONDecoder().decode(TouchBarConfiguration.self, from: $0) }
        #expect(saved?.excludedBundleIdentifiers == ["com.jetbrains.intellij"])
    }

    @MainActor @Test
    func send_showButtonTapped_enables_metrics_bar_and_persists_flag() async {
        let setCallStack = AllocatedUnfairLock<[String]>(initialState: [])
        let sut = MetricsSettings(.testDependencies(
            userDefaultsClient: testDependency(of: UserDefaultsClient.self) {
                $0.set = { value, key in
                    let entry = "set: \(key) = \(value ?? "nil")"
                    setCallStack.withLock { $0.append(entry) }
                }
            }
        ), showingMetricsBarNotesSheet: true)
        await sut.send(.showButtonTapped)
        #expect(!sut.showingMetricsBarNotesSheet)
        #expect(sut.showsMetricsBar)
        #expect(setCallStack.withLock(\.self) == ["set: SHOWS_METRICS_BAR = true"])
    }

    @MainActor @Test
    func send_monitorsSystemMetricsToggleSwitched_persists_configurations_and_notifies() async throws {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let activationRequests = AllocatedUnfairLock<[SystemInfoType: Bool]?>(initialState: nil)
        let storage = UserDefaultsClient.storage()
        let initialBarConfiguration = MetricsBarConfiguration(
            showsCPU: true,
            showsMemory: true,
            showsStorage: false,
            showsBattery: false,
            showsNetwork: false,
            visibleCustomMetricsSourceIDs: []
        )
        let encodedBarConfiguration = try JSONEncoder().encode(initialBarConfiguration)
        storage.lock.withLock { $0[.metricsBarConfiguration] = encodedBarConfiguration }
        let sut = MetricsSettings(.testDependencies(
            appStateClient: .testDependency(appState),
            systemInfoObserverClient: testDependency(of: SystemInfoObserverClient.self) {
                $0.toggleActivation = { requests in
                    activationRequests.withLock { $0 = requests }
                }
            },
            userDefaultsClient: storage.client
        ))
        await sut.send(.monitorsSystemMetricsToggleSwitched(.memory, false))
        #expect(!sut.systemMetricsConfiguration.monitorsMemory)
        let storedConfigurationData = storage.lock.withLock { $0[.systemMetricsConfiguration] }
        let storedConfiguration = try JSONDecoder().decode(
            SystemMetricsConfiguration.self,
            from: try #require(storedConfigurationData)
        )
        #expect(!storedConfiguration.monitorsMemory)
        let storedBarConfigurationData = storage.lock.withLock { $0[.metricsBarConfiguration] }
        let storedBarConfiguration = try JSONDecoder().decode(
            MetricsBarConfiguration.self,
            from: try #require(storedBarConfigurationData)
        )
        #expect(!storedBarConfiguration.showsMemory)
        #expect(activationRequests.withLock(\.self) == [.memory: false])
        #expect(appState.withLock(\.systemMetricsConfigurationChanges.latestValue) != nil)
        await sut.send(.monitorsSystemMetricsToggleSwitched(.memory, true))
        #expect(sut.systemMetricsConfiguration.monitorsMemory)
        let restoredBarConfigurationData = storage.lock.withLock { $0[.metricsBarConfiguration] }
        let restoredBarConfiguration = try JSONDecoder().decode(
            MetricsBarConfiguration.self,
            from: try #require(restoredBarConfigurationData)
        )
        #expect(restoredBarConfiguration.showsMemory)
        #expect(activationRequests.withLock(\.self) == [.memory: true])
    }

    @MainActor @Test
    func send_monitorsKeyboardBatteryToggleSwitched_on_starts_monitoring_and_opens_privacy_pane() async throws {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let startMonitoringCount = AllocatedUnfairLock<Int>(initialState: 0)
        let openCallStack = AllocatedUnfairLock<[URL]>(initialState: [])
        let storage = UserDefaultsClient.storage()
        let sut = MetricsSettings(.testDependencies(
            appStateClient: .testDependency(appState),
            nsWorkspaceClient: testDependency(of: NSWorkspaceClient.self) {
                $0.open = { url in
                    openCallStack.withLock { $0.append(url) }
                    return true
                }
            },
            keyboardBatteryObserverClient: testDependency(of: KeyboardBatteryObserverClient.self) {
                $0.startMonitoring = {
                    startMonitoringCount.withLock { $0 += 1 }
                }
            },
            userDefaultsClient: storage.client
        ))
        await sut.send(.monitorsKeyboardBatteryToggleSwitched(true))
        #expect(sut.keyboardBatteryConfiguration.isEnabled)
        let storedConfiguration = try JSONDecoder().decode(
            KeyboardBatteryConfiguration.self,
            from: try #require(storage.lock.withLock { $0[.keyboardBatteryConfiguration] })
        )
        #expect(storedConfiguration.isEnabled)
        #expect(startMonitoringCount.withLock(\.self) == 1)
        #expect(openCallStack.withLock(\.self) == [URL.privacyListenEvent])
    }

    @MainActor @Test
    func send_monitorsKeyboardBatteryToggleSwitched_off_stops_monitoring_and_clears_values() async throws {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let stopMonitoringCount = AllocatedUnfairLock<Int>(initialState: 0)
        let storage = UserDefaultsClient.storage()
        let sut = MetricsSettings(.testDependencies(
            appStateClient: .testDependency(appState),
            keyboardBatteryObserverClient: testDependency(of: KeyboardBatteryObserverClient.self) {
                $0.stopMonitoring = {
                    stopMonitoringCount.withLock { $0 += 1 }
                }
            },
            userDefaultsClient: storage.client
        ))
        appState.withLock {
            $0.metrics.send(Metrics(keyboardBatteries: [BluetoothKeyboardInfo(id: "k", name: "K6", percent: 36, status: .ok)]))
            $0.keyboardBatteries.send([BluetoothKeyboardInfo(id: "k", name: "K6", percent: 36, status: .ok)])
        }
        await sut.send(.monitorsKeyboardBatteryToggleSwitched(false))
        #expect(!sut.keyboardBatteryConfiguration.isEnabled)
        #expect(stopMonitoringCount.withLock(\.self) == 1)
        await waitUntil {
            appState.withLock(\.keyboardBatteries.latestValue) == []
                && appState.withLock(\.metrics.latestValue)?.keyboardBatteries == []
        }
    }

    @MainActor @Test
    func send_monitorsFanToggleSwitched_persists_configuration_and_notifies() async throws {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let activationRequests = AllocatedUnfairLock<[SystemInfoType: Bool]?>(initialState: nil)
        let storage = UserDefaultsClient.storage()
        let sut = MetricsSettings(.testDependencies(
            appStateClient: .testDependency(appState),
            systemInfoObserverClient: testDependency(of: SystemInfoObserverClient.self) {
                $0.toggleActivation = { requests in
                    activationRequests.withLock { $0 = requests }
                }
            },
            userDefaultsClient: storage.client
        ))
        await sut.send(.monitorsFanToggleSwitched(false))
        #expect(!sut.systemMetricsConfiguration.monitorsFan)
        let storedConfigurationData = storage.lock.withLock { $0[.systemMetricsConfiguration] }
        let storedConfiguration = try JSONDecoder().decode(
            SystemMetricsConfiguration.self,
            from: try #require(storedConfigurationData)
        )
        #expect(!storedConfiguration.monitorsFan)
        #expect(activationRequests.withLock(\.self) == nil)
        #expect(appState.withLock(\.systemMetricsConfigurationChanges.latestValue) != nil)
    }

    @MainActor @Test
    func send_monitorsSystemMetricsToggleSwitched_cpu_is_noop() async {
        let toggleActivationCount = AllocatedUnfairLock<Int>(initialState: 0)
        let sut = MetricsSettings(.testDependencies(
            systemInfoObserverClient: testDependency(of: SystemInfoObserverClient.self) {
                $0.toggleActivation = { _ in
                    toggleActivationCount.withLock { $0 += 1 }
                }
            }
        ))
        await sut.send(.monitorsSystemMetricsToggleSwitched(.cpu, false))
        #expect(toggleActivationCount.withLock(\.self) == 0)
    }

    @MainActor @Test
    func send_stockRefreshIntervalSelected_updates_and_persists_the_cadence() async {
        let storage = UserDefaultsClient.storage()
        let sut = MetricsSettings(.testDependencies(userDefaultsClient: storage.client))
        await sut.send(.stockRefreshIntervalSelected(5))
        #expect(sut.stockConfiguration.refreshInterval == 5)
        let saved = storage.lock.withLock { $0[.stockConfiguration] }
            .flatMap { try? JSONDecoder().decode(StockConfiguration.self, from: $0) }
        #expect(saved?.refreshInterval == 5)
    }

    @MainActor @Test
    func send_stockRefreshIntervalSelected_normalizes_an_unknown_option() async {
        let sut = MetricsSettings(.testDependencies())
        await sut.send(.stockRefreshIntervalSelected(7))
        #expect(sut.stockConfiguration.refreshInterval == 30)
    }

    @MainActor @Test
    func send_touchBarMemberStackAssignmentSelected_persists_and_emits_change() async throws {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let storage = UserDefaultsClient.storage()
        let sut = MetricsSettings(.testDependencies(
            appStateClient: .testDependency(appState),
            userDefaultsClient: storage.client
        ))
        await sut.send(.touchBarMemberStackAssignmentSelected(.metric(.storage), .newStack))
        #expect(sut.touchBarConfiguration.stacks.count == 1)
        #expect(sut.touchBarConfiguration.stacks[0].members == [.metric(.storage)])
        let saved = storage.lock.withLock { $0[.touchBarConfiguration] }
            .flatMap { try? JSONDecoder().decode(TouchBarConfiguration.self, from: $0) }
        #expect(saved?.stacks.first?.members == [.metric(.storage)])
        #expect(appState.withLock(\.touchBarConfigurationChanges.latestValue) != nil)
    }

    @MainActor @Test
    func send_touchBarMemberStackAssignmentSelected_moves_a_member_between_stacks() async {
        let storage = UserDefaultsClient.storage()
        let sut = MetricsSettings(.testDependencies(userDefaultsClient: storage.client))
        await sut.send(.touchBarMemberStackAssignmentSelected(.metric(.cpu), .newStack))
        let first = sut.touchBarConfiguration.stacks[0].id
        await sut.send(.touchBarMemberStackAssignmentSelected(.metric(.memory), .newStack))
        let second = sut.touchBarConfiguration.stacks[1].id
        await sut.send(.touchBarMemberStackAssignmentSelected(.metric(.cpu), .stack(second)))
        // Moving the only member out deletes the emptied first stack.
        #expect(sut.touchBarConfiguration.stacks.map(\.id) == [second])
        #expect(sut.touchBarConfiguration.stacks[0].members == [.metric(.memory), .metric(.cpu)])
        #expect(first != second)
    }

    @MainActor @Test
    func send_removeStockButtonTapped_detaches_the_stock_from_its_stack() async throws {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let stockID = UUID()
        let storage = UserDefaultsClient.storage(
            initialTouchBarConfiguration: TouchBarConfiguration(
                mode: .smart,
                excludedBundleIdentifiers: [],
                stacks: [TouchBarStack(members: [.stock(stockID)])]
            ),
            initialStockConfiguration: StockConfiguration(
                stocks: [Stock(id: stockID, symbol: "sh600519", abbreviation: "茅台")]
            )
        )
        let sut = MetricsSettings(.testDependencies(
            appStateClient: .testDependency(appState),
            userDefaultsClient: storage.client
        ))
        await sut.send(.removeStockButtonTapped(stockID))
        #expect(sut.stocks.isEmpty)
        #expect(sut.touchBarConfiguration.stacks.isEmpty)
        let saved = storage.lock.withLock { $0[.touchBarConfiguration] }
            .flatMap { try? JSONDecoder().decode(TouchBarConfiguration.self, from: $0) }
        #expect(saved?.stacks.isEmpty ?? false)
        #expect(appState.withLock(\.touchBarConfigurationChanges.latestValue) != nil)
    }
}
