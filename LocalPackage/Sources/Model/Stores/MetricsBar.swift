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

import AppKit
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
    public var stockConfiguration: StockConfiguration
    public var stockQuotes: [StockQuote]
    public var systemInfoBundle: SystemInfoBundle
    public var fanInfo: FanInfo?
    public var keyboardBatteries: [BluetoothKeyboardInfo]
    public var aiTokenUsage: AITokenUsage?
    public var customMetricsBundles: [CustomMetricsBundle]
    /// The Touch Bar runner's frames, normalized to the menu bar's 18pt
    /// height. Only populated when an image provider was injected, because
    /// the preset frame resources live in the UserInterface bundle.
    public private(set) var touchBarRunnerFrames: [NSImage] = []
    public private(set) var touchBarRunnerIsTemplate = true
    public private(set) var touchBarRunnerSpeed: Float = 1
    /// Bumped whenever the runner frames change; renderers diff on this
    /// instead of comparing NSImages by value.
    public private(set) var touchBarRunnerVersion = 0
    public let isPreview: Bool
    public let action: (Action) async -> Void

    @ObservationIgnored private let touchBarRunnerImageProvider: (@MainActor (String) -> NSImage?)?

    public init(
        _ appDependencies: AppDependencies,
        metricsBarConfiguration: MetricsBarConfiguration? = nil,
        touchBarConfiguration: TouchBarConfiguration? = nil,
        stockConfiguration: StockConfiguration? = nil,
        stockQuotes: [StockQuote] = [],
        systemInfoBundle: SystemInfoBundle = .init(),
        keyboardBatteries: [BluetoothKeyboardInfo] = [],
        customMetricsBundles: [CustomMetricsBundle] = [],
        touchBarRunnerImageProvider: (@MainActor (String) -> NSImage?)? = nil,
        isPreview: Bool? = nil,
        action: @escaping (Action) async -> Void = { _ in }
    ) {
        self.appStateClient = appDependencies.appStateClient
        self.userDefaultsRepository = .init(appDependencies.userDefaultsClient)
        self.logService = .init(appDependencies)
        self.metricsBarConfiguration = metricsBarConfiguration ?? userDefaultsRepository.metricsBarConfiguration
        self.touchBarConfiguration = touchBarConfiguration ?? userDefaultsRepository.touchBarConfiguration
        self.stockConfiguration = stockConfiguration ?? userDefaultsRepository.stockConfiguration
        self.stockQuotes = stockQuotes
        self.systemInfoBundle = systemInfoBundle
        self.keyboardBatteries = keyboardBatteries
        self.customMetricsBundles = customMetricsBundles
        self.touchBarRunnerImageProvider = touchBarRunnerImageProvider
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
            // Streams do not replay their latest value to new subscribers:
            // the stock service restores quotes at launch, before any bar is
            // on screen, so a bar appearing later must seed explicitly or it
            // shows nothing until the next poll (on a closed day: never).
            if let quotes = appStateClient.withLock(\.stocks.latestValue) {
                stockQuotes = quotes
            }
            // The runner bundle is only published when the runner changes, so
            // a bar appearing mid-session must seed from the latest values.
            if touchBarRunnerImageProvider != nil {
                if let bundle = appStateClient.withLock(\.runnerBundles.latestValue) {
                    updateTouchBarRunner(from: bundle)
                }
                if let speed = appStateClient.withLock(\.runnerSpeeds.latestValue) {
                    touchBarRunnerSpeed = speed
                }
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
                    group.addImmediateTask {
                        let stream = appStateClient.withLock(\.stockConfigurationChanges.stream)
                        for await _ in stream {
                            self?.updateStockConfiguration()
                        }
                    }
                    group.addImmediateTask {
                        let stream = appStateClient.withLock(\.stocks.stream)
                        for await quotes in stream {
                            self?.stockQuotes = quotes
                        }
                    }
                    if self?.touchBarRunnerImageProvider != nil {
                        group.addImmediateTask {
                            let stream = appStateClient.withLock(\.runnerBundles.stream)
                            for await value in stream {
                                self?.updateTouchBarRunner(from: value)
                            }
                        }
                        group.addImmediateTask {
                            let stream = appStateClient.withLock(\.runnerSpeeds.stream)
                            for await value in stream {
                                self?.touchBarRunnerSpeed = value
                            }
                        }
                    }
                }
            }

        case .viewDisappeared:
            task?.cancel()
            task = nil
        }
    }

    /// The configured stocks joined with their latest quotes, in configuration
    /// order. Stocks without a quote yet are skipped.
    public var stockIndicators: [StockIndicator] {
        stockConfiguration.stocks.compactMap { stock in
            guard let quote = stockQuotes.first(where: { $0.symbol == stock.symbol }),
                  let changePercent = quote.changePercent else {
                return nil
            }
            let direction: StockDirection = switch changePercent {
            case ..<0: .down
            case 0: .flat
            default: .up
            }
            return StockIndicator(
                id: stock.id,
                abbreviation: stock.abbreviation,
                name: quote.name,
                changePercent: changePercent,
                direction: direction,
                quote: quote
            )
        }
    }

    private func updateMetrics(from metrics: Metrics) {
        systemInfoBundle = metrics.systemInfoBundle
        fanInfo = metrics.fanInfo
        keyboardBatteries = metrics.keyboardBatteries
        aiTokenUsage = metrics.aiTokenUsage
        customMetricsBundles = metrics.customMetricsBundles
    }

    /// Converts a runner bundle into Touch Bar frame images, following the
    /// same pipeline as the menu bar's RunnerBar store: preset resources come
    /// from the injected provider, custom ones from PNG data, then flip and
    /// normalize to the 18pt line height.
    private func updateTouchBarRunner(from bundle: RunnerBundle) {
        guard let bundleImageProvider = touchBarRunnerImageProvider else { return }
        guard case let .keyFrameAnimation(frames) = bundle.displayFormat else { return }
        let isFlippedHorizontally = userDefaultsRepository.isFlippedHorizontally
        var images = [NSImage]()
        for frame in frames {
            let image: NSImage?
            switch frame {
            case let .preset(resourceName):
                image = bundleImageProvider(resourceName)
            case let .custom(data):
                image = NSImage(data: data)
            case .broken:
                image = nil
            }
            guard let image else { continue }
            image.flip(enabled: isFlippedHorizontally)
            image.normalize()
            image.isTemplate = bundle.runner.isTemplate
            images.append(image)
        }
        guard !images.isEmpty else { return }
        touchBarRunnerFrames = images
        touchBarRunnerIsTemplate = bundle.runner.isTemplate
        touchBarRunnerVersion += 1
    }

    private func updateMetricsBarConfiguration() {
        metricsBarConfiguration = userDefaultsRepository.metricsBarConfiguration
    }

    private func updateTouchBarConfiguration() {
        touchBarConfiguration = userDefaultsRepository.touchBarConfiguration
    }

    private func updateStockConfiguration() {
        stockConfiguration = userDefaultsRepository.stockConfiguration
    }

    /// The visible metrics rendered as plain icon + label values for the
    /// Touch Bar. The visible set is the Touch Bar's own configuration, which
    /// is independent of the menu bar metrics bar's visibility flags.
    public var touchBarIndicators: [TouchBarIndicator] {
        var indicators = [TouchBarIndicator]()
        if touchBarConfiguration.shows(.cpu), let cpuInfo = systemInfoBundle.cpuInfo {
            indicators.append(TouchBarIndicator(
                member: .metric(.cpu),
                systemIcon: cpuInfo.icon,
                primaryText: cpuInfo.percentage.menuBarDescription
            ))
        }
        if touchBarConfiguration.shows(.memory), let memoryInfo = systemInfoBundle.memoryInfo {
            indicators.append(TouchBarIndicator(
                member: .metric(.memory),
                systemIcon: memoryInfo.icon,
                primaryText: memoryInfo.percentage.menuBarDescription
            ))
        }
        if touchBarConfiguration.shows(.storage), let storageInfo = systemInfoBundle.storageInfo {
            indicators.append(TouchBarIndicator(
                member: .metric(.storage),
                systemIcon: storageInfo.icon,
                primaryText: storageInfo.percentage.menuBarDescription
            ))
        }
        if touchBarConfiguration.shows(.battery),
           let batteryInfo = systemInfoBundle.batteryInfo,
           batteryInfo.isInstalled {
            indicators.append(TouchBarIndicator(
                member: .metric(.battery),
                systemIcon: batteryInfo.icon,
                primaryText: batteryInfo.percentage.menuBarDescription
            ))
        }
        if touchBarConfiguration.shows(.network), let networkInfo = systemInfoBundle.networkInfo {
            indicators.append(TouchBarIndicator(
                member: .metric(.network),
                systemIcon: networkInfo.icon,
                primaryText: "\u{2B06}\(networkInfo.upload.menuBarDescription(type: .network))",
                secondaryText: "\u{2B07}\(networkInfo.download.menuBarDescription(type: .network))"
            ))
        }
        if touchBarConfiguration.shows(.fan),
           let fanInfo = fanInfo, !fanInfo.fans.isEmpty,
           fanInfo.fans[0].rpm > 0 {
            indicators.append(TouchBarIndicator(
                member: .metric(.fan),
                systemIcon: "fanblades",
                primaryText: "\(Int(fanInfo.fans[0].rpm.rounded()))"
            ))
        }
        if touchBarConfiguration.shows(.keyboardBattery),
           let keyboardBattery = keyboardBatteries.first {
            indicators.append(TouchBarIndicator(
                member: .metric(.keyboardBattery),
                systemIcon: "keyboard",
                primaryText: keyboardBattery.percent.map { "\($0)%" } ?? "--"
            ))
        }
        if touchBarConfiguration.shows(.aiTokenUsage),
           let aiTokenUsage = aiTokenUsage {
            indicators.append(TouchBarIndicator(
                member: .metric(.aiTokenUsage),
                systemIcon: "chart.bar.xaxis",
                primaryText: aiTokenUsage.barLabel
            ))
        }
        for bundle in customMetricsBundles where touchBarConfiguration.showsCustomMetrics(of: bundle.id) {
            indicators.append(TouchBarIndicator(
                member: .customMetric(bundle.id),
                systemIcon: bundle.snapshot.displaySymbol,
                primaryText: bundle.metricsBarLabel
            ))
        }
        return indicators
    }

    /// The visible metrics grouped into the slots the Touch Bar renders: each
    /// configured stack occupies one fixed slot and rotates through its
    /// members, everything else stays a plain single-item slot.
    public var touchBarMetricSlots: [TouchBarMetricSlot] {
        TouchBarSlotBuilder.metricSlots(
            indicators: touchBarIndicators,
            stacks: touchBarConfiguration.stacks
        )
    }

    public var touchBarStockSlots: [TouchBarStockSlot] {
        TouchBarSlotBuilder.stockSlots(
            indicators: stockIndicators,
            stacks: touchBarConfiguration.stacks
        )
    }

    public enum Action: Sendable {
        case viewAppeared(String)
        case viewDisappeared
    }
}
