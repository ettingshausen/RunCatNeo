/*
 StockIndicator.swift
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

public enum StockDirection: Sendable, Equatable {
    case up
    case down
    case flat
}

/// One configured stock joined with its latest quote, ready for the Touch Bar.
/// `direction` carries the domestic convention mapping (red up, green down) is
/// applied by the view.
public struct StockIndicator: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let abbreviation: String
    public let name: String
    public let changePercent: Double
    public let direction: StockDirection
    public let quote: StockQuote

    public init(id: UUID, abbreviation: String, name: String, changePercent: Double, direction: StockDirection, quote: StockQuote) {
        self.id = id
        self.abbreviation = abbreviation
        self.name = name
        self.changePercent = changePercent
        self.direction = direction
        self.quote = quote
    }
}
