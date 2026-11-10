/*
 Array+Extension.swift
 UserInterface

 Created by Takuto Nakamura on 2026/05/25.
 Copyright 2026 Kyome22 (Takuto Nakamura)

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

import CoreGraphics
import DataSource

extension Array where Element == CGFloat {
    func joined(separator: CGFloat) -> CGFloat {
        reduce(.zero) {
            if $0 > .zero {
                $0 + separator + $1
            } else {
                $0 + $1
            }
        }
    }
}

extension [BluetoothKeyboardInfo] {
    /// Picks the first keyboard worth showing, simulating a healthy reading in
    /// previews. A permission-denied row still occupies the bar so the user
    /// notices something needs attention; rows without any reading stay hidden
    /// rather than showing a misleading placeholder.
    func simulated(_ simulated: Bool) -> BluetoothKeyboardInfo? {
        let candidate = first { $0.status == .ok } ?? first { $0.status == .needsPermission }
        guard let candidate else { return nil }
        guard simulated, candidate.status == .ok, candidate.percent == nil else { return candidate }
        return BluetoothKeyboardInfo(
            id: candidate.id,
            name: candidate.name,
            percent: 76,
            changedAt: candidate.changedAt,
            lastSeenAt: candidate.lastSeenAt,
            status: candidate.status
        )
    }
}
