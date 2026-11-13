/*
 StockQuoteParser.swift
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

/// Parses Sina's `hq.sinajs.cn` response bodies. Field layouts differ per
/// market prefix, verified against live responses:
/// - A-share (`sh600519`): name=[0], prevClose=[2], price=[3], open=[1],
///   high=[4], low=[5]
/// - HK (`rt_hk00700`): nameEN=[0], nameZH=[1], open=[2], prevClose=[3],
///   high=[4], low=[5], price=[6], changeAmount=[7], changePercent=[8]
/// - US (`gb_aapl`): name=[0], price=[1], changePercent=[2], changeAmount=[4],
///   open=[5], high=[6], low=[7], prevClose=[26]
enum StockQuoteParser {
    static func parse(_ text: String) -> [StockQuote] {
        var quotes = [StockQuote]()
        for line in text.split(separator: "\n") {
            guard let assignmentRange = line.range(of: "=\""),
                  line.hasPrefix("var hq_str_") else {
                continue
            }
            let code = String(line[line.index(line.startIndex, offsetBy: 11)..<assignmentRange.lowerBound])
            let payload = line[assignmentRange.upperBound...]
            guard !code.isEmpty, payload.hasSuffix("\";") else { continue }
            let fields = payload
                .dropLast(2)
                .split(separator: ",", omittingEmptySubsequences: false)
                .map(String.init)
            guard let quote = quote(for: code, fields: fields) else { continue }
            quotes.append(quote)
        }
        return quotes
    }

    private static func quote(for code: String, fields: [String]) -> StockQuote? {
        // An unknown code comes back as an empty payload.
        guard fields.count > 2, !fields.joined().isEmpty else { return nil }
        switch true {
        case code.hasPrefix("rt_hk"):
            guard fields.count > 8 else { return nil }
            let livePrice = positive(fields[6])
            let prevClose = positive(fields[3])
            return StockQuote(
                symbol: code,
                name: fields[1],
                price: livePrice ?? prevClose,
                changePercent: livePrice == nil ? prevClose.map { _ in 0 } : Double(fields[8]),
                changeAmount: livePrice == nil ? prevClose.map { _ in 0 } : Double(fields[7]),
                open: positive(fields[2]),
                high: positive(fields[4]),
                low: positive(fields[5]),
                prevClose: prevClose
            )
        case code.hasPrefix("gb_"):
            guard fields.count > 26 else { return nil }
            let livePrice = positive(fields[1])
            let prevClose = positive(fields[26])
            return StockQuote(
                symbol: code,
                name: fields[0],
                price: livePrice ?? prevClose,
                changePercent: livePrice == nil ? prevClose.map { _ in 0 } : Double(fields[2]),
                changeAmount: livePrice == nil ? prevClose.map { _ in 0 } : Double(fields[4]),
                open: positive(fields[5]),
                high: positive(fields[6]),
                low: positive(fields[7]),
                prevClose: prevClose
            )
        case code.hasPrefix("sh") || code.hasPrefix("sz"):
            guard fields.count > 5, let prevClose = positive(fields[2]) else { return nil }
            let price = positive(fields[3]) ?? prevClose
            let changePercent = (price - prevClose) / prevClose * 100
            return StockQuote(
                symbol: code,
                name: fields[0],
                price: price,
                changePercent: changePercent,
                changeAmount: price - prevClose,
                open: positive(fields[1]),
                high: positive(fields[4]),
                low: positive(fields[5]),
                prevClose: prevClose
            )
        default:
            return nil
        }
    }

    /// Sina reports a zero price while a market has not opened yet (the
    /// pre-open call auction), and zero is never a real price, open, high or
    /// low. Treating it as missing keeps a pre-open stock on yesterday's close
    /// instead of displaying a "-100.00%" change.
    private static func positive(_ field: String) -> Double? {
        guard let value = Double(field), value > 0 else { return nil }
        return value
    }
}
