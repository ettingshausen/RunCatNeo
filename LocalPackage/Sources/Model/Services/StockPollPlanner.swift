/*
 StockPollPlanner.swift
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

/// Decides which configured symbols may be requested right now. A market is
/// skipped when its session is closed (night, lunch break, weekend) or when it
/// was already found closed today (a public holiday); a market that has not
/// been opened yet is probed instead of being polled blind.
enum StockPollPlanner {
    struct Plan: Equatable {
        /// Symbols safe to request immediately.
        var symbols: [String] = []
        /// Markets that must first be asked whether today is a trading day.
        var probeMarkets: [StockMarket] = []
    }

    static func plan(
        for stocks: [Stock],
        closedOn: [StockMarket: String],
        probedOn: [StockMarket: String],
        at now: Date
    ) -> Plan {
        var plan = Plan()
        for stock in stocks {
            guard let market = StockMarket(symbol: stock.symbol) else {
                // An unrecognized prefix is still polled rather than silently
                // dropped; the parser will ignore whatever comes back.
                plan.symbols.append(stock.symbol)
                continue
            }
            guard market.isOpen(at: now) else { continue }
            let today = market.localDateKey(now)
            guard closedOn[market] != today else { continue }
            if probedOn[market] == today {
                plan.symbols.append(stock.symbol)
            } else if market.canProbe(at: now), !plan.probeMarkets.contains(market) {
                plan.probeMarkets.append(market)
            }
        }
        return plan
    }

    /// A quote belongs to today when its timestamp falls on the market's
    /// current local date. A weekday whose freshest quote is still yesterday's
    /// is a public holiday or an exchange closure.
    static func isTradingDay(_ asOf: Date, of market: StockMarket, at now: Date) -> Bool {
        market.localDateKey(asOf) == market.localDateKey(now)
    }
}
