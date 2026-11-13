/*
 MetricsSettings.swift
 Model

 Created by Takuto Nakamura on 2026/05/23.
 Copyright 2026 Kyome22 (Takuto Nakamura)

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

import AppKit
import DataSource
import Foundation
import Observation
import SystemInfoKit

/// One excluded app as displayed in the settings list, with the name and icon
/// resolved from the bundle identifier on the fly.
public struct TouchBarExclusionRow {
    public let bundleIdentifier: String
    public let name: String?
    public let icon: NSImage?

    init(bundleIdentifier: String, name: String?, icon: NSImage?) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.icon = icon
    }
}

@MainActor @Observable
public final class MetricsSettings: Composable {
    private let appDependencies: AppDependencies
    private let appStateClient: AppStateClient
    private let userDefaultsRepository: UserDefaultsRepository
    private let logService: LogService
    private let systemMetricsService: SystemMetricsService
    private let keyboardBatteryService: KeyboardBatteryService
    private let aiTokenUsageService: AITokenUsageService
    private let touchBarMetricsService: TouchBarMetricsService
    private let stockService: StockService
    private let nsWorkspaceClient: NSWorkspaceClient

    @ObservationIgnored private var task: Task<Void, Never>?

    public var showsMetricsBar: Bool
    public var showingMetricsBarNotesSheet: Bool
    public var systemMetricsConfiguration: SystemMetricsConfiguration
    public var metricsBarConfiguration: MetricsBarConfiguration
    public var keyboardBatteryConfiguration: KeyboardBatteryConfiguration
    public var aiTokenUsageConfiguration: AITokenUsageConfiguration
    public var showsMetricsBarOnTouchBar: Bool
    public var touchBarConfiguration: TouchBarConfiguration
    public var showingTouchBarAppImporter: Bool
    public var stockConfiguration: StockConfiguration
    public var stockEditor: StockEditor?
    public var lastExternalFrontmostApplication: FrontmostApplicationInfo?
    public let isTouchBarHardwareAvailable: Bool
    public let customMetricsSettings: CustomMetricsSettings
    public let action: (Action) async -> Void

    public init(
        _ appDependencies: AppDependencies,
        showsMetricsBar: Bool? = nil,
        showingMetricsBarNotesSheet: Bool = false,
        systemMetricsConfiguration: SystemMetricsConfiguration? = nil,
        aiTokenUsageConfiguration: AITokenUsageConfiguration? = nil,
        customMetricsSettings: CustomMetricsSettings? = nil,
        action: @escaping (Action) async -> Void = { _ in }
    ) {
        self.appDependencies = appDependencies
        self.appStateClient = appDependencies.appStateClient
        self.userDefaultsRepository = .init(appDependencies.userDefaultsClient)
        self.logService = .init(appDependencies)
        self.systemMetricsService = .init(appDependencies)
        self.keyboardBatteryService = .init(appDependencies)
        self.aiTokenUsageService = .init(appDependencies)
        self.touchBarMetricsService = .init(appDependencies)
        self.stockService = .init(appDependencies)
        self.nsWorkspaceClient = appDependencies.nsWorkspaceClient
        self.showsMetricsBar = showsMetricsBar ?? userDefaultsRepository.showsMetricsBar
        self.showingMetricsBarNotesSheet = showingMetricsBarNotesSheet
        self.systemMetricsConfiguration = systemMetricsConfiguration ?? userDefaultsRepository.systemMetricsConfiguration
        self.metricsBarConfiguration = userDefaultsRepository.metricsBarConfiguration
        self.keyboardBatteryConfiguration = userDefaultsRepository.keyboardBatteryConfiguration
        self.aiTokenUsageConfiguration = aiTokenUsageConfiguration ?? userDefaultsRepository.aiTokenUsageConfiguration
        self.showsMetricsBarOnTouchBar = userDefaultsRepository.showsMetricsBarOnTouchBar
        self.touchBarConfiguration = userDefaultsRepository.touchBarConfiguration
        self.showingTouchBarAppImporter = false
        self.stockConfiguration = userDefaultsRepository.stockConfiguration
        self.lastExternalFrontmostApplication = appStateClient.withLock(\.lastExternalFrontmostApplication)
        self.isTouchBarHardwareAvailable = TouchBarMetricsService.isTouchBarHardwareAvailable
        weak var weakSelf: MetricsSettings? = nil
        self.customMetricsSettings = customMetricsSettings ??
            .init(appDependencies, action: { await weakSelf?.send(.customMetricsSettings($0)) })
        self.action = action
        weakSelf = self
    }

    public func reduce(_ action: Action) async {
        switch action {
        case let .viewAppeared(screenName):
            logService.notice(.screenView(name: screenName))
            task?.cancel()
            task = Task.immediate { [weak self, appStateClient, nsWorkspaceClient] in
                await withTaskGroup { group in
                    group.addImmediateTask { [weak self] in
                        let stream = appStateClient.withLock(\.systemMetricsConfigurationChanges.stream)
                        for await _ in stream {
                            self?.refreshSystemMetricsConfiguration()
                        }
                    }
                    group.addImmediateTask { [weak self] in
                        let stream = nsWorkspaceClient.frontmostApplicationChanges().values
                        for await info in stream {
                            self?.rememberExternalFrontmostApplication(info)
                        }
                    }
                    group.addImmediateTask { [weak self] in
                        let stream = appStateClient.withLock(\.touchBarConfigurationChanges.stream)
                        for await _ in stream {
                            self?.refreshTouchBarConfiguration()
                        }
                    }
                    group.addImmediateTask { [weak self] in
                        let stream = appStateClient.withLock(\.stockConfigurationChanges.stream)
                        for await _ in stream {
                            self?.refreshStockConfiguration()
                        }
                    }
                }
            }

        case .viewDisappeared:
            task?.cancel()
            task = nil

        case let .showMetricsBarToggleSwitched(isOn):
            if isOn {
                showingMetricsBarNotesSheet = true
            } else {
                showsMetricsBar = false
                userDefaultsRepository.showsMetricsBar = false
            }

        case .changedMyMindButtonTapped:
            showingMetricsBarNotesSheet = false

        case .showButtonTapped:
            showingMetricsBarNotesSheet = false
            showsMetricsBar = true
            userDefaultsRepository.showsMetricsBar = true

        case let .monitorsSystemMetricsToggleSwitched(type, isOn):
            func setShow(_ isOn: Bool, shows: inout Bool) {
                shows = isOn
            }
            var metricsBarConfiguration = userDefaultsRepository.metricsBarConfiguration
            // CPU is always monitored for the Dashboard graphs; its switch only
            // controls menu bar visibility.
            var needsActivationChange = true
            switch type {
            case .cpu:
                metricsBarConfiguration.showsCPU = isOn
                needsActivationChange = false
            case .memory:
                systemMetricsConfiguration.monitorsMemory = isOn
                setShow(isOn, shows: &metricsBarConfiguration.showsMemory)
            case .storage:
                systemMetricsConfiguration.monitorsStorage = isOn
                setShow(isOn, shows: &metricsBarConfiguration.showsStorage)
            case .battery:
                systemMetricsConfiguration.monitorsBattery = isOn
                setShow(isOn, shows: &metricsBarConfiguration.showsBattery)
            case .network:
                systemMetricsConfiguration.monitorsNetwork = isOn
                setShow(isOn, shows: &metricsBarConfiguration.showsNetwork)
            }
            userDefaultsRepository.systemMetricsConfiguration = systemMetricsConfiguration
            userDefaultsRepository.metricsBarConfiguration = metricsBarConfiguration
            self.metricsBarConfiguration = metricsBarConfiguration
            if needsActivationChange {
                systemMetricsService.toggleSystemMetricsActivation(type: type, isOn: isOn)
            }
            systemMetricsService.emitConfigurationChange()

        case let .monitorsCustomMetricsToggleSwitched(id, isOn):
            var metricsBarConfiguration = userDefaultsRepository.metricsBarConfiguration
            if isOn {
                metricsBarConfiguration.visibleCustomMetricsSourceIDs.insert(id)
            } else {
                metricsBarConfiguration.visibleCustomMetricsSourceIDs.remove(id)
            }
            userDefaultsRepository.metricsBarConfiguration = metricsBarConfiguration
            self.metricsBarConfiguration = metricsBarConfiguration
            systemMetricsService.emitConfigurationChange()

        case let .monitorsFanToggleSwitched(isOn):
            var metricsBarConfiguration = userDefaultsRepository.metricsBarConfiguration
            metricsBarConfiguration.showsFan = isOn
            userDefaultsRepository.metricsBarConfiguration = metricsBarConfiguration
            self.metricsBarConfiguration = metricsBarConfiguration
            systemMetricsConfiguration.monitorsFan = isOn
            userDefaultsRepository.systemMetricsConfiguration = systemMetricsConfiguration
            systemMetricsService.emitConfigurationChange()

        case let .monitorsKeyboardBatteryToggleSwitched(isOn):
            var configuration = userDefaultsRepository.keyboardBatteryConfiguration
            configuration.isEnabled = isOn
            userDefaultsRepository.keyboardBatteryConfiguration = configuration
            keyboardBatteryConfiguration = configuration
            var metricsBarConfiguration = userDefaultsRepository.metricsBarConfiguration
            metricsBarConfiguration.showsKeyboardBattery = isOn
            userDefaultsRepository.metricsBarConfiguration = metricsBarConfiguration
            self.metricsBarConfiguration = metricsBarConfiguration
            if isOn {
                keyboardBatteryService.startMonitoring()
                _ = nsWorkspaceClient.open(URL.privacyListenEvent)
            } else {
                keyboardBatteryService.stopMonitoring()
                keyboardBatteryService.updateMetrics(from: [])
            }
            systemMetricsService.emitConfigurationChange()

        case let .monitorsAITokenUsageToggleSwitched(isOn):
            var configuration = userDefaultsRepository.aiTokenUsageConfiguration
            configuration.isEnabled = isOn
            userDefaultsRepository.aiTokenUsageConfiguration = configuration
            aiTokenUsageConfiguration = configuration
            var metricsBarConfiguration = userDefaultsRepository.metricsBarConfiguration
            metricsBarConfiguration.showsAITokenUsage = isOn
            userDefaultsRepository.metricsBarConfiguration = metricsBarConfiguration
            self.metricsBarConfiguration = metricsBarConfiguration
            if isOn {
                aiTokenUsageService.startMonitoring()
            } else {
                aiTokenUsageService.stopMonitoring()
            }
            systemMetricsService.emitConfigurationChange()

        case .addStockButtonTapped:
            stockEditor = StockEditor(
                appDependencies,
                existingStocks: stockConfiguration.stocks,
                action: { [weak self] in await self?.send(.stockEditor($0)) }
            )

        case let .stockEditor(action):
            switch action {
            case .cancelButtonTapped:
                stockEditor = nil
            case let .stockAdded(stock):
                stockEditor = nil
                var configuration = stockConfiguration
                configuration.stocks.append(stock)
                stockConfiguration = configuration
                userDefaultsRepository.stockConfiguration = configuration
                stockService.emitConfigurationChange()
            default:
                return
            }

        case let .removeStockButtonTapped(id):
            var configuration = stockConfiguration
            configuration.stocks.removeAll { $0.id == id }
            stockConfiguration = configuration
            userDefaultsRepository.stockConfiguration = configuration
            stockService.emitConfigurationChange()

        case let .stockRefreshIntervalSelected(seconds):
            var configuration = stockConfiguration
            configuration.refreshInterval = StockConfiguration.normalizedRefreshInterval(seconds)
            stockConfiguration = configuration
            userDefaultsRepository.stockConfiguration = configuration
            // The service re-reads the cadence on its next tick, and a config
            // change also refreshes the quotes right away.
            stockService.emitConfigurationChange()

        case let .showsMetricsBarOnTouchBarToggleSwitched(isOn):
            showsMetricsBarOnTouchBar = isOn
            userDefaultsRepository.showsMetricsBarOnTouchBar = isOn
            touchBarMetricsService.emitConfigurationChange()

        case let .touchBarMetricToggleSwitched(metric, isOn):
            var configuration = touchBarConfiguration
            if isOn {
                configuration.visibleMetrics.insert(metric)
            } else {
                configuration.visibleMetrics.remove(metric)
            }
            touchBarConfiguration = configuration
            userDefaultsRepository.touchBarConfiguration = configuration
            touchBarMetricsService.emitConfigurationChange()
            // A metric can only appear once it is being collected, so turning
            // one on also starts its monitoring. Turning one off leaves
            // monitoring alone: the menu bar bar may still be using it.
            if isOn {
                startMonitoringIfNeeded(for: metric)
            }

        case let .touchBarStockPrioritySwitched(prioritizeStocks):
            var configuration = touchBarConfiguration
            configuration.prioritizeStocks = prioritizeStocks
            touchBarConfiguration = configuration
            userDefaultsRepository.touchBarConfiguration = configuration
            touchBarMetricsService.emitConfigurationChange()

        case let .touchBarCustomMetricsToggleSwitched(id, isOn):
            var configuration = touchBarConfiguration
            if isOn {
                configuration.visibleCustomMetricsSourceIDs.insert(id)
            } else {
                configuration.visibleCustomMetricsSourceIDs.remove(id)
            }
            touchBarConfiguration = configuration
            userDefaultsRepository.touchBarConfiguration = configuration
            touchBarMetricsService.emitConfigurationChange()

        case let .touchBarDisplayModeSelected(mode):
            touchBarConfiguration.mode = mode
            userDefaultsRepository.touchBarConfiguration = touchBarConfiguration
            touchBarMetricsService.emitConfigurationChange()

        case let .touchBarAppImporterPresented(isPresented):
            showingTouchBarAppImporter = isPresented

        case let .touchBarAppsImported(urls):
            var configuration = touchBarConfiguration
            for url in urls {
                guard let bundleIdentifier = nsWorkspaceClient.bundleIdentifier(url),
                      !configuration.excludedBundleIdentifiers.contains(bundleIdentifier) else { continue }
                configuration.excludedBundleIdentifiers.append(bundleIdentifier)
            }
            touchBarConfiguration = configuration
            userDefaultsRepository.touchBarConfiguration = configuration
            touchBarMetricsService.emitConfigurationChange()

        case .touchBarExcludeCurrentAppButtonTapped:
            // Clicking the button makes this app frontmost, so the app to
            // exclude is the last frontmost app that was not us.
            var candidate = lastExternalFrontmostApplication
            if candidate == nil {
                let live = nsWorkspaceClient.frontmostApplication()
                if live?.bundleIdentifier != Bundle.main.bundleIdentifier {
                    candidate = live
                }
            }
            guard let application = candidate,
                  application.bundleIdentifier != Bundle.main.bundleIdentifier,
                  !touchBarConfiguration.excludedBundleIdentifiers.contains(application.bundleIdentifier) else { return }
            touchBarConfiguration.excludedBundleIdentifiers.append(application.bundleIdentifier)
            userDefaultsRepository.touchBarConfiguration = touchBarConfiguration
            touchBarMetricsService.emitConfigurationChange()

        case let .touchBarExcludedAppRemoved(bundleIdentifier):
            touchBarConfiguration.excludedBundleIdentifiers.removeAll { $0 == bundleIdentifier }
            userDefaultsRepository.touchBarConfiguration = touchBarConfiguration
            touchBarMetricsService.emitConfigurationChange()

        case .customMetricsSettings:
            return
        }
    }

    /// Whether the per-metric table shows the Touch Bar column. When it does
    /// not, the Touch Bar section is meaningless and stays hidden.
    public var isTouchBarMetricsColumnVisible: Bool {
        isTouchBarHardwareAvailable && showsMetricsBarOnTouchBar
    }

    public var stocks: [Stock] {
        stockConfiguration.stocks
    }

    /// The custom metric sources, offered as per-source toggles in the Touch
    /// Bar section.
    public var customMetricsSources: [CustomMetricsSource] {
        customMetricsSettings.customMetricsSources
    }

    /// The excluded apps as display rows with resolved names and icons.
    public var touchBarExclusionRows: [TouchBarExclusionRow] {
        touchBarConfiguration.excludedBundleIdentifiers.map { bundleIdentifier in
            TouchBarExclusionRow(
                bundleIdentifier: bundleIdentifier,
                name: nsWorkspaceClient.applicationName(bundleIdentifier),
                icon: nsWorkspaceClient.applicationIcon(bundleIdentifier)
            )
        }
    }

    /// Enables data collection for a metric the Touch Bar is about to show.
    /// Switching it on from the Touch Bar must not depend on the menu bar
    /// section, which can be hidden.
    private func startMonitoringIfNeeded(for metric: TouchBarMetric) {
        switch metric {
        case .cpu:
            // CPU is always collected.
            return
        case .network:
            guard !systemMetricsConfiguration.monitorsNetwork else { return }
            systemMetricsConfiguration.monitorsNetwork = true
            systemMetricsService.toggleSystemMetricsActivation(type: .network, isOn: true)
        case .memory:
            guard !systemMetricsConfiguration.monitorsMemory else { return }
            systemMetricsConfiguration.monitorsMemory = true
            systemMetricsService.toggleSystemMetricsActivation(type: .memory, isOn: true)
        case .storage:
            guard !systemMetricsConfiguration.monitorsStorage else { return }
            systemMetricsConfiguration.monitorsStorage = true
            systemMetricsService.toggleSystemMetricsActivation(type: .storage, isOn: true)
        case .battery:
            guard !systemMetricsConfiguration.monitorsBattery else { return }
            systemMetricsConfiguration.monitorsBattery = true
            systemMetricsService.toggleSystemMetricsActivation(type: .battery, isOn: true)
        case .fan:
            guard !systemMetricsConfiguration.monitorsFan else { return }
            systemMetricsConfiguration.monitorsFan = true
        case .keyboardBattery:
            guard !keyboardBatteryConfiguration.isEnabled else { return }
            var configuration = keyboardBatteryConfiguration
            configuration.isEnabled = true
            userDefaultsRepository.keyboardBatteryConfiguration = configuration
            keyboardBatteryConfiguration = configuration
            keyboardBatteryService.startMonitoring()
        case .aiTokenUsage:
            guard !aiTokenUsageConfiguration.isEnabled else { return }
            var configuration = aiTokenUsageConfiguration
            configuration.isEnabled = true
            userDefaultsRepository.aiTokenUsageConfiguration = configuration
            aiTokenUsageConfiguration = configuration
            aiTokenUsageService.startMonitoring()
        }
        userDefaultsRepository.systemMetricsConfiguration = systemMetricsConfiguration
        systemMetricsService.emitConfigurationChange()
    }

    private func refreshSystemMetricsConfiguration() {
        systemMetricsConfiguration = userDefaultsRepository.systemMetricsConfiguration
        metricsBarConfiguration = userDefaultsRepository.metricsBarConfiguration
    }

    private func refreshTouchBarConfiguration() {
        touchBarConfiguration = userDefaultsRepository.touchBarConfiguration
        showsMetricsBarOnTouchBar = userDefaultsRepository.showsMetricsBarOnTouchBar
    }

    private func refreshStockConfiguration() {
        stockConfiguration = userDefaultsRepository.stockConfiguration
    }

    private func rememberExternalFrontmostApplication(_ info: FrontmostApplicationInfo?) {
        guard let info, info.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        lastExternalFrontmostApplication = info
        appStateClient.withLock { $0.lastExternalFrontmostApplication = info }
    }

    public enum Action: Sendable {
        case viewAppeared(String)
        case viewDisappeared
        case showMetricsBarToggleSwitched(Bool)
        case changedMyMindButtonTapped
        case showButtonTapped
        case monitorsSystemMetricsToggleSwitched(SystemInfoType, Bool)
        case monitorsFanToggleSwitched(Bool)
        case monitorsKeyboardBatteryToggleSwitched(Bool)
        case monitorsAITokenUsageToggleSwitched(Bool)
        case monitorsCustomMetricsToggleSwitched(UUID, Bool)
        case showsMetricsBarOnTouchBarToggleSwitched(Bool)
        case touchBarDisplayModeSelected(TouchBarDisplayMode)
        case touchBarAppImporterPresented(Bool)
        case touchBarAppsImported([URL])
        case touchBarMetricToggleSwitched(TouchBarMetric, Bool)
        case addStockButtonTapped
        case stockEditor(StockEditor.Action)
        case removeStockButtonTapped(UUID)
        case stockRefreshIntervalSelected(Int)
        case touchBarStockPrioritySwitched(Bool)
        case touchBarCustomMetricsToggleSwitched(UUID, Bool)
        case touchBarExcludeCurrentAppButtonTapped
        case touchBarExcludedAppRemoved(String)
        case customMetricsSettings(CustomMetricsSettings.Action)
    }
}
