/*
 TouchBarSlot.swift
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

/// One position in the Touch Bar metrics row: either a single metric or a
/// stack of metrics that rotates through that position. `id` is stable across
/// data updates (`stack:<uuid>` or the member key) so the view can keep the
/// rotation phase.
public struct TouchBarMetricSlot: Sendable, Equatable, Identifiable {
    public let id: String
    public let indicators: [TouchBarIndicator]

    public var isStack: Bool { indicators.count > 1 }

    public init(id: String, indicators: [TouchBarIndicator]) {
        self.id = id
        self.indicators = indicators
    }
}

/// The stock equivalent of `TouchBarMetricSlot`.
public struct TouchBarStockSlot: Sendable, Equatable, Identifiable {
    public let id: String
    public let indicators: [StockIndicator]

    public var isStack: Bool { indicators.count > 1 }

    public init(id: String, indicators: [StockIndicator]) {
        self.id = id
        self.indicators = indicators
    }
}
