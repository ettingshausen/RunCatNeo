/*
 TouchBarSlotBuilder.swift
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

/// Groups the visible indicators into the slots the Touch Bar renders. A
/// stack takes the position of its first visible member; members that are
/// missing right now (a fan at zero RPM, a quote that has not arrived yet) are
/// skipped, and a stack reduced to one member renders as a plain cell.
public enum TouchBarSlotBuilder {
    public static func metricSlots(
        indicators: [TouchBarIndicator],
        stacks: [TouchBarStack]
    ) -> [TouchBarMetricSlot] {
        var emitted = Set<UUID>()
        var slots = [TouchBarMetricSlot]()
        for indicator in indicators {
            guard let stack = stacks.first(where: { $0.members.contains(indicator.member) }) else {
                slots.append(TouchBarMetricSlot(
                    id: indicator.member.slotID,
                    indicators: [indicator]
                ))
                continue
            }
            guard !emitted.contains(stack.id) else { continue }
            emitted.insert(stack.id)
            // Rotate in the order the user added members, not in render order.
            let members = stack.members.compactMap { member in
                indicators.first { $0.member == member }
            }
            slots.append(TouchBarMetricSlot(
                id: stack.slotID,
                indicators: members
            ))
        }
        return slots
    }

    public static func stockSlots(
        indicators: [StockIndicator],
        stacks: [TouchBarStack]
    ) -> [TouchBarStockSlot] {
        var emitted = Set<UUID>()
        var slots = [TouchBarStockSlot]()
        for indicator in indicators {
            let member = TouchBarMember.stock(indicator.id)
            guard let stack = stacks.first(where: { $0.members.contains(member) }) else {
                slots.append(TouchBarStockSlot(
                    id: member.slotID,
                    indicators: [indicator]
                ))
                continue
            }
            guard !emitted.contains(stack.id) else { continue }
            emitted.insert(stack.id)
            let members = stack.members.compactMap { member -> StockIndicator? in
                guard case let .stock(id) = member else { return nil }
                return indicators.first { $0.id == id }
            }
            slots.append(TouchBarStockSlot(
                id: stack.slotID,
                indicators: members
            ))
        }
        return slots
    }
}
