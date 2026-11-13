/*
 StockServiceTests.swift
 ModelTests

 Created by ettingshausen on 2026/11/14.
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

import AllocatedUnfairLock
import Foundation
import Testing

@testable import DataSource
@testable import Model

@MainActor
struct StockServiceTests {
    private let appState = AllocatedUnfairLock<AppState>(initialState: .init())

    /// A local Saturday afternoon, so every configured market is closed and
    /// the planner never offers a probe or a poll.
    private var saturday: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 15))!
    }

    private func makeService(
        stocks: [Stock],
        savedQuotes: [StockQuote] = [],
        fetch: @escaping @Sendable ([String]) async throws -> String = { _ in throw URLError(.unsupportedURL) }
    ) -> (service: StockService, repository: UserDefaultsRepository, fetches: AllocatedUnfairLock<[[String]]>) {
        let store = AllocatedUnfairLock<[String: Data]>(initialState: [:])
        if !stocks.isEmpty, let data = try? JSONEncoder().encode(StockConfiguration(stocks: stocks, refreshInterval: 30)) {
            store.withLock { $0[String.stockConfiguration] = data }
        }
        if !savedQuotes.isEmpty, let data = try? JSONEncoder().encode(savedQuotes) {
            store.withLock { $0[String.stockQuotes] = data }
        }
        let fetches = AllocatedUnfairLock<[[String]]>(initialState: [])
        let userDefaultsClient = testDependency(of: UserDefaultsClient.self) {
            $0.data = { key in store.withLock { $0[key] } }
            $0.set = { value, key in
                guard let data = value as? Data else { return }
                store.withLock { $0[key] = data }
            }
            $0.removeObject = { key in store.withLock { $0[key] = nil } }
        }
        let service = StockService(.testDependencies(
            appStateClient: .testDependency(appState),
            dateClient: testDependency(of: DateClient.self) { [saturday] in $0.now = { saturday } },
            stockClient: testDependency(of: StockClient.self) {
                $0.fetch = { symbols in
                    fetches.withLock { $0.append(symbols) }
                    return try await fetch(symbols)
                }
            },
            userDefaultsClient: userDefaultsClient
        ))
        return (service, UserDefaultsRepository(userDefaultsClient), fetches)
    }

    // MARK: - Merge

    @Test
    func merge_replaces_known_symbols_and_keeps_uncovered_ones() {
        let keep = StockQuote(symbol: "sh600519", name: "贵州茅台", price: 1410.27, changePercent: 0.57)
        let stale = StockQuote(symbol: "sz000001", name: "平安银行", price: 11.00, changePercent: 0.10)
        let fresh = StockQuote(symbol: "sz000001", name: "平安银行", price: 11.52, changePercent: 0.35)
        #expect(StockService.merge(current: [keep, stale], fresh: [fresh]) == [keep, fresh])
    }

    // MARK: - Restore & seed

    @Test
    func start_publishes_persisted_quotes_without_requesting() async {
        let saved = [StockQuote(symbol: "sz000001", name: "平安银行", price: 11.02, changePercent: 0.5)]
        let (sut, _, fetches) = makeService(
            stocks: [Stock(id: UUID(), symbol: "sz000001", abbreviation: "平安")],
            savedQuotes: saved
        )
        sut.start()
        let published = await waitUntil { [appState] in
            appState.withLock(\.stocks.latestValue) == saved
        }
        sut.stop()
        #expect(published)
        try? await Task.sleep(for: .milliseconds(300))
        // The cached level covers the watchlist, so a closed day costs no request.
        #expect(fetches.withLock { $0 }.isEmpty)
    }

    @Test
    func closed_day_seeds_uncovered_symbols_once_and_merges_with_the_cached_level() async {
        let cached = StockQuote(symbol: "sz000001", name: "平安银行", price: 11.02, changePercent: 0.5)
        // Friday's close for the symbol the cache does not know yet.
        let line = #"var hq_str_sz000002="万科A,8.500,8.480,8.520,8.550,8.440,8.520,8.510,3237294,4536814518.000,1655,8.520,100,8.510,400,8.500,400,8.490,100,8.480,200,8.520,100,8.520,100,8.530,500,8.540,100,8.550,2026-11-13,15:00:00,00,D|2000|2820540.00";"#
        let (sut, repository, fetches) = makeService(
            stocks: [
                Stock(id: UUID(), symbol: "sz000001", abbreviation: "平安"),
                Stock(id: UUID(), symbol: "sz000002", abbreviation: "万科"),
            ],
            savedQuotes: [cached],
            fetch: { _ in line }
        )
        sut.start()
        let merged = await waitUntil { [appState] in
            appState.withLock(\.stocks.latestValue)?.map(\.symbol) == ["sz000001", "sz000002"]
        }
        sut.stop()
        #expect(merged)
        #expect(fetches.withLock { $0 } == [["sz000002"]])
        // A later tick must not re-request anything on a closed day.
        sut.emitConfigurationChange()
        try? await Task.sleep(for: .milliseconds(300))
        #expect(fetches.withLock { $0 }.count == 1)
        // The merged level is persisted for the next launch.
        #expect(repository.stockQuotes.map(\.symbol) == ["sz000001", "sz000002"])
    }
}
