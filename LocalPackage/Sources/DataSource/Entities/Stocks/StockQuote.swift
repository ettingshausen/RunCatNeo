/*
 StockQuote.swift
 DataSource

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

import Foundation

/// A parsed snapshot for one configured stock. Fields a market does not report
/// stay nil; the Touch Bar skips a stock until it has a change percent.
public struct StockQuote: Sendable, Equatable {
    public let symbol: String
    public let name: String
    public let price: Double?
    public let changePercent: Double?
    public let changeAmount: Double?
    public let open: Double?
    public let high: Double?
    public let low: Double?
    public let prevClose: Double?
    /// When the market last published this quote. The poll planner compares
    /// its market-local date with today's to detect public holidays, when a
    /// weekday still carries the previous session's data.
    public let asOf: Date?

    public init(
        symbol: String,
        name: String,
        price: Double?,
        changePercent: Double?,
        changeAmount: Double? = nil,
        open: Double? = nil,
        high: Double? = nil,
        low: Double? = nil,
        prevClose: Double? = nil,
        asOf: Date? = nil
    ) {
        self.symbol = symbol
        self.name = name
        self.price = price
        self.changePercent = changePercent
        self.changeAmount = changeAmount
        self.open = open
        self.high = high
        self.low = low
        self.prevClose = prevClose
        self.asOf = asOf
    }
}
