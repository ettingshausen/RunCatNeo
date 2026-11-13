/*
 Stock.swift
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

/// One configured watchlist entry. `symbol` is the raw Sina code —
/// `sh600519` / `sz000001` for A-shares, `rt_hk00700` for Hong Kong,
/// `gb_aapl` for US markets.
public struct Stock: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var symbol: String
    public var abbreviation: String

    public init(id: UUID, symbol: String, abbreviation: String) {
        self.id = id
        self.symbol = symbol
        self.abbreviation = abbreviation
    }
}
