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

import DataSource
import Foundation
import Observation
import SystemInfoKit

@MainActor @Observable
public final class MetricsSettings: Composable {
    private let appStateClient: AppStateClient
    private let userDefaultsRepository: UserDefaultsRepository
    private let logService: LogService
    private let systemMetricsService: SystemMetricsService
    private let keyboardBatteryService: KeyboardBatteryService
    private let aiTokenUsageService: AITokenUsageService
    private let nsWorkspaceClient: NSWorkspaceClient

    @ObservationIgnored private var task: Task<Void, Never>?

    public var showsMetricsBar: Bool
    public var showingMetricsBarNotesSheet: Bool
    public var systemMetricsConfiguration: SystemMetricsConfiguration
    public var keyboardBatteryConfiguration: KeyboardBatteryConfiguration
    public var aiTokenUsageConfiguration: AITokenUsageConfiguration
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
        self.appStateClient = appDependencies.appStateClient
        self.userDefaultsRepository = .init(appDependencies.userDefaultsClient)
        self.logService = .init(appDependencies)
        self.systemMetricsService = .init(appDependencies)
        self.keyboardBatteryService = .init(appDependencies)
        self.aiTokenUsageService = .init(appDependencies)
        self.nsWorkspaceClient = appDependencies.nsWorkspaceClient
        self.showsMetricsBar = showsMetricsBar ?? userDefaultsRepository.showsMetricsBar
        self.showingMetricsBarNotesSheet = showingMetricsBarNotesSheet
        self.systemMetricsConfiguration = systemMetricsConfiguration ?? userDefaultsRepository.systemMetricsConfiguration
        self.keyboardBatteryConfiguration = userDefaultsRepository.keyboardBatteryConfiguration
        self.aiTokenUsageConfiguration = aiTokenUsageConfiguration ?? userDefaultsRepository.aiTokenUsageConfiguration
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
            task = Task.immediate { [weak self, appStateClient] in
                let stream = appStateClient.withLock(\.systemMetricsConfigurationChanges.stream)
                for await _ in stream {
                    self?.refreshSystemMetricsConfiguration()
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
            func overwrite(isOn: Bool, shows: inout Bool) {
                shows = shows && isOn
            }
            var metricsBarConfiguration = userDefaultsRepository.metricsBarConfiguration
            switch type {
            case .cpu:
                return
            case .memory:
                systemMetricsConfiguration.monitorsMemory = isOn
                overwrite(isOn: isOn, shows: &metricsBarConfiguration.showsMemory)
            case .storage:
                systemMetricsConfiguration.monitorsStorage = isOn
                overwrite(isOn: isOn, shows: &metricsBarConfiguration.showsStorage)
            case .battery:
                systemMetricsConfiguration.monitorsBattery = isOn
                overwrite(isOn: isOn, shows: &metricsBarConfiguration.showsBattery)
            case .network:
                systemMetricsConfiguration.monitorsNetwork = isOn
                overwrite(isOn: isOn, shows: &metricsBarConfiguration.showsNetwork)
            }
            userDefaultsRepository.systemMetricsConfiguration = systemMetricsConfiguration
            userDefaultsRepository.metricsBarConfiguration = metricsBarConfiguration
            systemMetricsService.toggleSystemMetricsActivation(type: type, isOn: isOn)
            systemMetricsService.emitConfigurationChange()

        case let .monitorsFanToggleSwitched(isOn):
            if !isOn {
                var metricsBarConfiguration = userDefaultsRepository.metricsBarConfiguration
                metricsBarConfiguration.showsFan = false
                userDefaultsRepository.metricsBarConfiguration = metricsBarConfiguration
            }
            systemMetricsConfiguration.monitorsFan = isOn
            userDefaultsRepository.systemMetricsConfiguration = systemMetricsConfiguration
            systemMetricsService.emitConfigurationChange()

        case let .monitorsKeyboardBatteryToggleSwitched(isOn):
            var configuration = userDefaultsRepository.keyboardBatteryConfiguration
            configuration.isEnabled = isOn
            userDefaultsRepository.keyboardBatteryConfiguration = configuration
            keyboardBatteryConfiguration = configuration
            if isOn {
                keyboardBatteryService.startMonitoring()
                _ = nsWorkspaceClient.open(URL.privacyListenEvent)
            } else {
                keyboardBatteryService.stopMonitoring()
                keyboardBatteryService.updateMetrics(from: [])
                var metricsBarConfiguration = userDefaultsRepository.metricsBarConfiguration
                metricsBarConfiguration.showsKeyboardBattery = false
                userDefaultsRepository.metricsBarConfiguration = metricsBarConfiguration
            }
            systemMetricsService.emitConfigurationChange()

        case let .monitorsAITokenUsageToggleSwitched(isOn):
            var configuration = userDefaultsRepository.aiTokenUsageConfiguration
            configuration.isEnabled = isOn
            userDefaultsRepository.aiTokenUsageConfiguration = configuration
            aiTokenUsageConfiguration = configuration
            if isOn {
                aiTokenUsageService.startMonitoring()
            } else {
                aiTokenUsageService.stopMonitoring()
                var metricsBarConfiguration = userDefaultsRepository.metricsBarConfiguration
                metricsBarConfiguration.showsAITokenUsage = false
                userDefaultsRepository.metricsBarConfiguration = metricsBarConfiguration
            }
            systemMetricsService.emitConfigurationChange()

        case .customMetricsSettings:
            return
        }
    }

    private func refreshSystemMetricsConfiguration() {
        systemMetricsConfiguration = userDefaultsRepository.systemMetricsConfiguration
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
        case customMetricsSettings(CustomMetricsSettings.Action)
    }
}
