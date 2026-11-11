/*
 Int+Extension.swift
 DataSource

 Created by ettingshausen on 2026/11/11.
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

extension Int {
    /// Compact token count for narrow menu-bar labels: 912, 1.2K, 88.4M, 1.23B.
    public var formattedTokenCount: String {
        func abbreviated(_ value: Double, unit: String) -> String {
            if value >= 100 {
                return String(format: "%.0f%@", value, unit)
            } else {
                let text = String(format: "%.1f", value)
                return text.hasSuffix(".0") ? String(text.prefix(text.count - 2)) + unit : text + unit
            }
        }
        if self < 0 {
            return "0"
        }
        let value = Double(self)
        if value >= 1_000_000_000 {
            return abbreviated(value / 1_000_000_000, unit: "B")
        } else if value >= 1_000_000 {
            return abbreviated(value / 1_000_000, unit: "M")
        } else if value >= 1_000 {
            return abbreviated(value / 1_000, unit: "K")
        }
        return String(self)
    }
}
