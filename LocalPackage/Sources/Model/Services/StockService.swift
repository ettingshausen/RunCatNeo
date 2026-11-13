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

    /// The editor validates a new symbol by fetching its live quote.
    func fetchQuote(symbol: String) async throws -> StockQuote {
        let text = try await stockClient.fetch([symbol])
        guard let quote = StockQuoteParser.parse(text).first else {
            throw RCNError.stock(.fetchFailed)
        }
        return quote
    }

    private func refreshQuotes() {
        let symbols = userDefaultsRepository.stockConfiguration.stocks.map(\.symbol)
        guard !symbols.isEmpty else { return }
        Task.immediate { [weak self, stockClient, appStateClient] in
            guard let text = try? await stockClient.fetch(symbols), !text.isEmpty else { return }
            let quotes = StockQuoteParser.parse(text)
            guard !quotes.isEmpty else { return }
            appStateClient.send(\.stocks, quotes)
        }
    }
}
