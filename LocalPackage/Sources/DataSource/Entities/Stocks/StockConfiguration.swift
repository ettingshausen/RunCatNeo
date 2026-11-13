/*
 StockConfiguration.swift
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

public struct StockConfiguration: Codable, Sendable, Equatable {
    /// The poll cadence offered in settings. Sina serves its quotes a few
    /// seconds behind the tick, so there is no point in going faster.
    public static let refreshIntervalOptions = [5, 10, 15, 30]
    public static let defaultRefreshInterval = 30

    public var stocks: [Stock]
    /// Seconds between quote requests.
    public var refreshInterval: Int

    public static let `default` = Self(stocks: [], refreshInterval: defaultRefreshInterval)

    public init(stocks: [Stock], refreshInterval: Int = defaultRefreshInterval) {
        self.stocks = stocks
        self.refreshInterval = Self.normalizedRefreshInterval(refreshInterval)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stocks = try container.decodeIfPresent([Stock].self, forKey: .stocks) ?? []
        // Configurations written before the cadence was configurable used 30s.
        refreshInterval = Self.normalizedRefreshInterval(
            try container.decodeIfPresent(Int.self, forKey: .refreshInterval) ?? Self.defaultRefreshInterval
        )
    }

    /// Keeps a hand-edited or migrated value inside the offered options.
    public static func normalizedRefreshInterval(_ seconds: Int) -> Int {
        refreshIntervalOptions.contains(seconds) ? seconds : defaultRefreshInterval
    }
}
