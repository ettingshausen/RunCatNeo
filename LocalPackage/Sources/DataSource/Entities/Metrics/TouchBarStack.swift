/*
 TouchBarStack.swift
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

/// One item that can take part in a Touch Bar stack: a built-in metric, a
/// custom metrics source, or a watchlist stock. Membership is persisted inside
/// the Touch Bar configuration, so the value survives independently of whether
/// the item is currently visible.
public enum TouchBarMember: Sendable, Equatable, Hashable {
    case metric(TouchBarMetric)
    case customMetric(UUID)
    case stock(UUID)

    /// A stable token for the persisted configuration. Unknown tokens decode
    /// to nil and are dropped, so a future member kind cannot corrupt the
    /// whole configuration.
    public var key: String {
        switch self {
        case let .metric(metric): "metric:\(metric.rawValue)"
        case let .customMetric(id): "custom:\(id.uuidString)"
        case let .stock(id): "stock:\(id.uuidString)"
        }
    }

    public init?(key: String) {
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "metric":
            guard let metric = TouchBarMetric(rawValue: parts[1]) else { return nil }
            self = .metric(metric)
        case "custom":
            guard let id = UUID(uuidString: parts[1]) else { return nil }
            self = .customMetric(id)
        case "stock":
            guard let id = UUID(uuidString: parts[1]) else { return nil }
            self = .stock(id)
        default:
            return nil
        }
    }

    /// System and custom metrics render as the same kind of cell, so they can
    /// share a stack. Stocks use the stock cell and stay in their own stacks.
    public var belongsToStockGroup: Bool {
        if case .stock = self { return true }
        return false
    }

    /// Stable identity of the single-item slot this member renders in.
    public var slotID: String {
        "member:\(key)"
    }
}

/// A set of Touch Bar items that share one fixed slot and rotate through it.
public struct TouchBarStack: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var members: [TouchBarMember]

    public init(id: UUID = UUID(), members: [TouchBarMember]) {
        self.id = id
        self.members = members
    }

    /// A stack holds either metrics or stocks, never both: the two groups are
    /// rendered and prioritized separately.
    public func isCompatible(with member: TouchBarMember) -> Bool {
        guard let first = members.first else { return true }
        return first.belongsToStockGroup == member.belongsToStockGroup
    }

    /// Stable identity of the stack's slot, shared with the view's rotation
    /// phase and the slot builder.
    public var slotID: String {
        "stack:\(id.uuidString)"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case members
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let keys = try container.decodeIfPresent([String].self, forKey: .members) ?? []
        members = keys.compactMap(TouchBarMember.init(key:))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(members.map(\.key), forKey: .members)
    }
}

/// Where a Touch Bar item should live, chosen from the settings menu.
public enum TouchBarStackAssignment: Sendable, Equatable {
    case independent
    case stack(UUID)
    case newStack
}

extension TouchBarConfiguration {
    /// Four stacks of rotating items is already more than the 621pt bar can
    /// show side by side; the cap also keeps the numbering short.
    public static let maxStacks = 4

    public func stack(containing member: TouchBarMember) -> TouchBarStack? {
        stacks.first { $0.members.contains(member) }
    }

    /// Stacks an item may join: same group and not already holding it.
    public func stacks(compatibleWith member: TouchBarMember) -> [TouchBarStack] {
        stacks.filter { $0.isCompatible(with: member) }
    }

    /// Removes the item from every stack (an item belongs to at most one) and
    /// applies the requested destination. Empty stacks disappear so the
    /// settings numbering stays contiguous.
    public mutating func assign(_ member: TouchBarMember, to assignment: TouchBarStackAssignment) {
        detach(member)
        switch assignment {
        case .independent:
            break
        case let .stack(id):
            guard let index = stacks.firstIndex(where: { $0.id == id }),
                  stacks[index].isCompatible(with: member) else {
                return
            }
            stacks[index].members.append(member)
        case .newStack:
            guard stacks.count < Self.maxStacks else { return }
            stacks.append(TouchBarStack(members: [member]))
        }
    }

    public mutating func detach(_ member: TouchBarMember) {
        for index in stacks.indices {
            stacks[index].members.removeAll { $0 == member }
        }
        stacks.removeAll { $0.members.isEmpty }
    }

    /// Drops duplicates, empty stacks, members of the wrong group and
    /// anything past the stack cap. Persisted data can outlive the stocks and
    /// custom sources it references, so the decoder must not trust it.
    public static func normalizedStacks(_ stacks: [TouchBarStack]) -> [TouchBarStack] {
        var seen = Set<TouchBarMember>()
        var result = [TouchBarStack]()
        for stack in stacks {
            guard result.count < maxStacks else { break }
            let stockGroup = stack.members.first?.belongsToStockGroup
            var members = [TouchBarMember]()
            for member in stack.members where !seen.contains(member) {
                guard let stockGroup, member.belongsToStockGroup == stockGroup else { continue }
                seen.insert(member)
                members.append(member)
            }
            if !members.isEmpty {
                result.append(TouchBarStack(id: stack.id, members: members))
            }
        }
        return result
    }
}
