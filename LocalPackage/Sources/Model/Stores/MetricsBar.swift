/*
 MetricsBar.swift
 Model

 Created by Takuto Nakamura on 2026/05/24.
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
public final class MetricsBar: Composable {
    private let appStateClient: AppStateClient
    private let userDefaultsRepository: UserDefaultsRepository
    private let logService: LogService

    @ObservationIgnored private var task: Task<Void, Never>?

    public var metricsBarConfiguration: MetricsBarConfiguration
    public var touchBarConfiguration: TouchBarConfiguration
    public var systemInfoBundle: SystemInfoBundle
    public var fanInfo: FanInfo?
    public var keyboardBatteries: [BluetoothKeyboardInfo]
    public var aiTokenUsage: AITokenUsage?
    public var customMetricsBundles: [CustomMetricsBundle]
    public let isPreview: Bool
    public let action: (Action) async -> Void

    public init(
        _ appDependencies: AppDependencies,
        metricsBarConfiguration: MetricsBarConfiguration? = nil,
        touchBarConfiguration: TouchBarConfiguration? = nil,
        systemInfoBundle: SystemInfoBundle = .init(),
        keyboardBatteries: [BluetoothKeyboardInfo] = [],
        customMetricsBundles: [CustomMetricsBundle] = [],
        isPreview: Bool? = nil,
        action: @escaping (Action) async -> Void = { _ in }
    ) {
        self.appStateClient = appDependencies.appStateClient
        self.userDefaultsRepository = .init(appDependencies.userDefaultsClient)
        self.logService = .init(appDependencies)
        self.metricsBarConfiguration = metricsBarConfiguration ?? userDefaultsRepository.metricsBarConfiguration
        self.touchBarConfiguration = touchBarConfiguration ?? userDefaultsRepository.touchBarConfiguration
        self.systemInfoBundle = systemInfoBundle
        self.keyboardBatteries = keyboardBatteries
        self.customMetricsBundles = customMetricsBundles
        self.isPreview = isPreview ?? ProcessInfo.isPreview
        self.action = action
    }

    public func reduce(_ action: Action) async {
        switch action {
        case let .viewAppeared(screenName):
            logService.notice(.screenView(name: screenName))
            if let metrics = appStateClient.withLock(\.metrics.latestValue) {
                updateMetrics(from: metrics)
            }
            task?.cancel()
            task = Task.immediate { [weak self, appStateClient] in
                await withTaskGroup { group in
                    group.addImmediateTask {
                        let stream = appStateClient.withLock(\.metrics.stream)
                        for await value in stream {
                            self?.updateMetrics(from: value)
                        }
                    }
                    group.addImmediateTask {
                        let stream = appStateClient.withLock(\.systemMetricsConfigurationChanges.stream)
                        for await _ in stream {
                            self?.updateMetricsBarConfiguration()
                        }
                    }
                    group.addImmediateTask {
                        let stream = appStateClient.withLock(\.customMetricsConfigurationChanges.stream)
                        for await _ in stream {
                            self?.updateMetricsBarConfiguration()
                        }
                    }
                    group.addImmediateTask {
                        let stream = appStateClient.withLock(\.touchBarConfigurationChanges.stream)
                        for await _ in stream {
                            self?.updateTouchBarConfiguration()
                        }
                    }
                }
            }

        case .viewDisappeared:
            task?.cancel()
            task = nil
        }
    }

    private func updateMetrics(from metrics: Metrics) {
        systemInfoBundle = metrics.systemInfoBundle
        fanInfo = metrics.fanInfo
        keyboardBatteries = metrics.keyboardBatteries
        aiTokenUsage = metrics.aiTokenUsage
        customMetricsBundles = metrics.customMetricsBundles
    }

    private func updateMetricsBarConfiguration() {
        metricsBarConfiguration = userDefaultsRepository.metricsBarConfiguration
    }

    private func updateTouchBarConfiguration() {
        touchBarConfiguration = userDefaultsRepository.touchBarConfiguration
    }

    /// The visible metrics rendered as plain icon + label values for the
    /// Touch Bar. The visible set is the Touch Bar's own configuration, which
    /// is independent of the menu bar metrics bar's visibility flags.
    public var touchBarIndicators: [TouchBarIndicator] {
        var indicators = [TouchBarIndicator]()
        if touchBarConfiguration.shows(.cpu), let cpuInfo = systemInfoBundle.cpuInfo {
            indicators.append(TouchBarIndicator(
                systemIcon: cpuInfo.icon,
                primaryText: cpuInfo.percentage.menuBarDescription
            ))
        }
        if touchBarConfiguration.shows(.memory), let memoryInfo = systemInfoBundle.memoryInfo {
            indicators.append(TouchBarIndicator(
                systemIcon: memoryInfo.icon,
                primaryText: memoryInfo.percentage.menuBarDescription
            ))
        }
        if touchBarConfiguration.shows(.storage), let storageInfo = systemInfoBundle.storageInfo {
            indicators.append(TouchBarIndicator(
                systemIcon: storageInfo.icon,
                primaryText: storageInfo.percentage.menuBarDescription
            ))
        }
        if touchBarConfiguration.shows(.battery),
           let batteryInfo = systemInfoBundle.batteryInfo,
           batteryInfo.isInstalled {
            indicators.append(TouchBarIndicator(
                systemIcon: batteryInfo.icon,
                primaryText: batteryInfo.percentage.menuBarDescription
            ))
        }
        if touchBarConfiguration.shows(.network), let networkInfo = systemInfoBundle.networkInfo {
            indicators.append(TouchBarIndicator(
                systemIcon: networkInfo.icon,
                primaryText: "\u{2B06}\(networkInfo.upload.menuBarDescription(type: .network))",
                secondaryText: "\u{2B07}\(networkInfo.download.menuBarDescription(type: .network))"
            ))
        }
        if touchBarConfiguration.shows(.fan),
           let fanInfo = fanInfo, !fanInfo.fans.isEmpty,
           fanInfo.fans[0].rpm > 0 {
            indicators.append(TouchBarIndicator(
                systemIcon: "fanblades",
                primaryText: "\(Int(fanInfo.fans[0].rpm.rounded()))"
            ))
        }
        if touchBarConfiguration.shows(.keyboardBattery),
           let keyboardBattery = keyboardBatteries.first {
            indicators.append(TouchBarIndicator(
                systemIcon: "keyboard",
                primaryText: keyboardBattery.percent.map { "\($0)%" } ?? "--"
            ))
        }
        if touchBarConfiguration.shows(.aiTokenUsage),
           let aiTokenUsage = aiTokenUsage {
            indicators.append(TouchBarIndicator(
                systemIcon: "chart.bar.xaxis",
                primaryText: aiTokenUsage.barLabel
            ))
        }
        for bundle in customMetricsBundles where touchBarConfiguration.showsCustomMetrics(of: bundle.id) {
            indicators.append(TouchBarIndicator(
                systemIcon: bundle.snapshot.displaySymbol,
                primaryText: bundle.metricsBarLabel
            ))
        }
        return indicators
    }

    public enum Action: Sendable {
        case viewAppeared(String)
        case viewDisappeared
    }
}
