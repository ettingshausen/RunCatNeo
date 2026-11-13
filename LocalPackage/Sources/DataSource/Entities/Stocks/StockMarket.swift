/*
 StockMarket.swift
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

/// The exchanges the Sina watchlist can address. Each market has its own
/// timezone and regular sessions, so the service only asks for quotes while a
/// configured market is actually trading.
public enum StockMarket: String, CaseIterable, Sendable, Equatable {
    case china
    case hongKong
    case unitedStates

    public init?(symbol: String) {
        switch true {
        case symbol.hasPrefix("sh"), symbol.hasPrefix("sz"), symbol.hasPrefix("bj"):
            self = .china
        case symbol.hasPrefix("rt_hk"), symbol.hasPrefix("hk"):
            self = .hongKong
        case symbol.hasPrefix("gb_"):
            self = .unitedStates
        default:
            return nil
        }
    }

    public var timeZone: TimeZone {
        switch self {
        // These identifiers ship with macOS; the fallback keeps a corrupt
        // timezone database from crashing the app.
        case .china: TimeZone(identifier: "Asia/Shanghai") ?? .current
        case .hongKong: TimeZone(identifier: "Asia/Hong_Kong") ?? .current
        case .unitedStates: TimeZone(identifier: "America/New_York") ?? .current
        }
    }

    /// Regular trading sessions in local time as half-open minute ranges.
    /// Lunch breaks are excluded; so are pre- and after-hours, which only
    /// produce stale prices for the watchlist.
    public var sessions: [Range<Int>] {
        switch self {
        case .china: [9 * 60 + 30 ..< 11 * 60 + 30, 13 * 60 ..< 15 * 60]
        case .hongKong: [9 * 60 + 30 ..< 12 * 60, 13 * 60 ..< 16 * 60]
        case .unitedStates: [9 * 60 + 30 ..< 16 * 60]
        }
    }

    /// How long after the opening bell the market's own quotes are trustworthy
    /// enough to decide whether today is a trading day. Domestic quotes flip
    /// to today's date during the call auction, but a couple of minutes of
    /// margin keep a slow first update from looking like a holiday; US quotes
    /// can lag a few minutes at the open.
    public var probeDelayMinutes: Int {
        switch self {
        case .china, .hongKong: 2
        case .unitedStates: 5
        }
    }

    /// A broad index used only to answer "is today a trading day": any one
    /// symbol of the market would do, but an index is never suspended.
    public var probeSymbol: String {
        switch self {
        case .china: "sh000001"
        case .hongKong: "rt_hkHSI"
        case .unitedStates: "gb_dji"
        }
    }

    public func isOpen(at date: Date) -> Bool {
        guard isTradingDay(at: date) else { return false }
        let minute = minuteOfDay(at: date)
        return sessions.contains { $0.contains(minute) }
    }

    public func isTradingDay(at date: Date) -> Bool {
        let weekday = components(at: date).weekday ?? 1
        // Gregorian weekdays: Sunday = 1, Saturday = 7.
        return (2...6).contains(weekday)
    }

    /// True from shortly after the first session opens, when a quote's date
    /// reflects whether the exchange traded today.
    public func canProbe(at date: Date) -> Bool {
        guard isTradingDay(at: date) else { return false }
        let start = sessions[0].lowerBound + probeDelayMinutes
        return minuteOfDay(at: date) >= start
    }

    /// The market-local calendar date as `yyyy-MM-dd`, used to remember that a
    /// market was found closed (a holiday) for the rest of that day.
    public func localDateKey(_ date: Date) -> String {
        let components = components(at: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private func components(at date: Date) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.dateComponents([.year, .month, .day, .weekday, .hour, .minute], from: date)
    }

    private func minuteOfDay(at date: Date) -> Int {
        let components = components(at: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
