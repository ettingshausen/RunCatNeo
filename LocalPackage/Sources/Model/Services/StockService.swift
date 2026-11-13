/*
 StockService.swift
 Model

 Created by ettingshausen on 2026/11/13.
 Copyright 2026 ettingshausen

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

/// Polls Sina for the configured watchlist and publishes parsed quotes.
/// A failed or empty response keeps the previous quotes on the Touch Bar.
@MainActor
final class StockService {
    /// The poll cadence is user-configurable; sleeping in short chunks lets a
    /// cadence change take effect without waiting out the old interval.
    private static let maxSleepChunk: Double = 5

    private let appDependencies: AppDependencies
    private let appStateClient: AppStateClient
    private let logService: LogService
    private let stockClient: StockClient
    private let userDefaultsRepository: UserDefaultsRepository
    private var task: Task<Void, Never>?
    /// Poll bookkeeping: a market found closed (a public holiday) is
    /// remembered for the rest of its local date, and a market only starts
    /// polling after its opening probe confirmed that today is a trading day.
    private var closedOn: [StockMarket: String] = [:]
    private var probedOn: [StockMarket: String] = [:]
    private var isPolling = false

    init(_ appDependencies: AppDependencies) {
        self.appDependencies = appDependencies
        self.appStateClient = appDependencies.appStateClient
        self.logService = .init(appDependencies)
        self.stockClient = appDependencies.stockClient
        self.userDefaultsRepository = .init(appDependencies.userDefaultsClient)
    }

    func start() {
        task?.cancel()
        task = Task.immediate { [weak self] in
            await self?.observe()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func emitConfigurationChange() {
        appStateClient.send(\.stockConfigurationChanges, ())
    }

    private func observe() async {
        let appStateClient = self.appStateClient
        await withTaskGroup { group in
            group.addImmediateTask { [weak self] in
                let stream = appStateClient.withLock(\.stockConfigurationChanges.stream)
                for await _ in stream {
                    self?.refreshQuotes()
                }
            }
            group.addImmediateTask { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    self.refreshQuotes()
                    await self.sleepUntilNextPoll()
                }
            }
        }
    }

    /// Sleeps the configured interval, re-reading it every chunk so a change
    /// in settings applies to the cycle already in flight.
    private func sleepUntilNextPoll() async {
        var elapsed: Double = 0
        while !Task.isCancelled {
            let interval = Double(userDefaultsRepository.stockConfiguration.refreshInterval)
            guard elapsed < interval else { return }
            let chunk = min(Self.maxSleepChunk, interval)
            try? await Task.sleep(for: .seconds(chunk))
            elapsed += chunk
        }
    }

    /// Requests quotes only for markets that are open right now. Closed
    /// sessions, weekends and holidays cost no network traffic: a market is
    /// confirmed open once per day by probing its index quote, and a weekday
    /// whose index still carries the previous session is treated as a holiday.
    private func refreshQuotes() {
        let stocks = userDefaultsRepository.stockConfiguration.stocks
        guard !stocks.isEmpty, !isPolling else { return }
        let now = Date()
        let plan = StockPollPlanner.plan(
            for: stocks,
            closedOn: closedOn,
            probedOn: probedOn,
            at: now
        )
        guard !plan.symbols.isEmpty || !plan.probeMarkets.isEmpty else { return }

        isPolling = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isPolling = false }
            var symbols = plan.symbols
            for market in plan.probeMarkets {
                // A failed probe is retried on the next tick rather than
                // guessing whether the market is open.
                guard let asOf = await self.probe(market) else { continue }
                if StockPollPlanner.isTradingDay(asOf, of: market, at: now) {
                    self.probedOn[market] = market.localDateKey(now)
                    symbols.append(contentsOf: stocks
                        .filter { StockMarket(symbol: $0.symbol) == market }
                        .map(\.symbol))
                } else {
                    self.closedOn[market] = market.localDateKey(now)
                }
            }
            guard !symbols.isEmpty else { return }
            await self.poll(symbols)
        }
    }

    private func probe(_ market: StockMarket) async -> Date? {
        guard let text = try? await stockClient.fetch([market.probeSymbol]) else { return nil }
        return StockQuoteParser.parse(text).first?.asOf
    }

    private func poll(_ symbols: [String]) async {
        guard let text = try? await stockClient.fetch(symbols), !text.isEmpty else { return }
        let quotes = StockQuoteParser.parse(text)
        guard !quotes.isEmpty else { return }
        appStateClient.send(\.stocks, quotes)
    }
}
