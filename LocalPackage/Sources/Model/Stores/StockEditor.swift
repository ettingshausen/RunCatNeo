/*
 StockEditor.swift
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

import DataSource
import Foundation
import Observation

/// Sheet editor for one watchlist stock. Confirming validates the Sina code by
/// fetching its live quote — an unknown code would otherwise silently never
/// appear on the Touch Bar — and reports the finished `Stock` to the parent.
@MainActor @Observable
public final class StockEditor: Composable, Identifiable {
    public static let maxStocks = 5

    private let stockClient: StockClient
    private let existingSymbols: [String]
    private let existingCount: Int
    private let logService: LogService

    public let id = UUID()
    public var symbol: String
    public var abbreviation: String
    public var isFetching = false
    public var error: RCNError?
    public var showingAlert = false
    public let action: (Action) async -> Void

    public var canAdd: Bool {
        !symbol.isEmpty
    }

    public init(
        _ appDependencies: AppDependencies,
        existingStocks: [Stock],
        symbol: String = "",
        abbreviation: String = "",
        action: @escaping (Action) async -> Void = { _ in }
    ) {
        self.stockClient = appDependencies.stockClient
        self.existingSymbols = existingStocks.map(\.symbol)
        self.existingCount = existingStocks.count
        self.logService = .init(appDependencies)
        self.symbol = symbol
        self.abbreviation = abbreviation
        self.action = action
    }

    public func reduce(_ action: Action) async {
        switch action {
        case .addButtonTapped:
            guard let symbol = Self.normalizedSymbol(symbol) else {
                await send(.errorOccurred(.stock(.invalidSymbol)))
                return
            }
            guard !existingSymbols.contains(symbol) else {
                await send(.errorOccurred(.stock(.duplicateSymbol)))
                return
            }
            guard existingCount < Self.maxStocks else {
                await send(.errorOccurred(.stock(.limitExceeded)))
                return
            }
            isFetching = true
            defer { isFetching = false }
            do {
                let text = try await stockClient.fetch([symbol])
                guard let quote = StockQuoteParser.parse(text).first else {
                    throw RCNError.stock(.fetchFailed)
                }
                let abbreviation = abbreviation.trimmingCharacters(in: .whitespaces)
                let stock = Stock(
                    id: UUID(),
                    symbol: symbol,
                    abbreviation: abbreviation.isEmpty ? String(quote.name.prefix(8)) : abbreviation
                )
                logService.notice(.stockAdded(symbol: symbol))
                await send(.stockAdded(stock))
            } catch let error as RCNError {
                await send(.errorOccurred(error))
            } catch {
                logService.critical(.unknown(error))
                await send(.errorOccurred(.stock(.fetchFailed)))
            }

        case .cancelButtonTapped:
            return

        case let .errorOccurred(error):
            self.error = error
            showingAlert = true

        case .stockAdded:
            return
        }
    }

    /// Turns whatever the user typed into a Sina code. Bare forms are routed by
    /// A-share board rules (60/68 → Shanghai, 00/30/02 → Shenzhen, 43/83/87/92 →
    /// Beijing), 4–5 digit numbers become Hong Kong codes (zero-padded to five),
    /// and letter codes become US tickers. Prefixed Sina codes pass through.
    static func normalizedSymbol(_ raw: String) -> String? {
        let symbol = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !symbol.isEmpty else { return nil }
        if symbol.hasPrefix("sh") || symbol.hasPrefix("sz") || symbol.hasPrefix("bj") {
            let digits = symbol.dropFirst(2)
            return digits.count == 6 && digits.allSatisfy(\.isNumber) ? symbol : nil
        }
        if symbol.hasPrefix("rt_hk") {
            let digits = symbol.dropFirst(5)
            return (1...5).contains(digits.count) && digits.allSatisfy(\.isNumber) ? symbol : nil
        }
        if symbol.hasPrefix("gb_") {
            let body = symbol.dropFirst(3)
            return (1...10).contains(body.count)
                && body.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." } ? symbol : nil
        }
        if symbol.count == 6, symbol.allSatisfy(\.isNumber) {
            let shBoards = ["60", "68"]
            let szBoards = ["00", "30", "02"]
            let bjBoards = ["43", "83", "87", "92"]
            if shBoards.contains(where: symbol.hasPrefix) { return "sh" + symbol }
            if szBoards.contains(where: symbol.hasPrefix) { return "sz" + symbol }
            if bjBoards.contains(where: symbol.hasPrefix) { return "bj" + symbol }
            return nil
        }
        if (1...5).contains(symbol.count), symbol.allSatisfy(\.isNumber) {
            return "rt_hk" + String(repeating: "0", count: 5 - symbol.count) + symbol
        }
        if (1...10).contains(symbol.count),
           symbol.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." }) {
            return "gb_" + symbol
        }
        return nil
    }

    static func isValidSymbol(_ symbol: String) -> Bool {
        if symbol.hasPrefix("sh") || symbol.hasPrefix("sz") {
            let digits = symbol.dropFirst(2)
            return digits.count == 6 && digits.allSatisfy(\.isNumber)
        }
        if symbol.hasPrefix("rt_hk") {
            let digits = symbol.dropFirst(5)
            return (4...5).contains(digits.count) && digits.allSatisfy(\.isNumber)
        }
        if symbol.hasPrefix("gb_") {
            let body = symbol.dropFirst(3)
            return (1...10).contains(body.count)
                && body.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." }
        }
        return false
    }

    public enum Action: Sendable {
        case addButtonTapped
        case cancelButtonTapped
        case stockAdded(Stock)
        case errorOccurred(RCNError)
    }
}
