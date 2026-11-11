/*
 AITokenUsage.swift
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

import Foundation

/// The AI coding tools whose local usage logs RunCat can read.
public enum AIToolKind: String, Sendable, CaseIterable, Codable {
    case claudeCode
    case zcode
    case codex
}

/// One day of token usage for a single tool, read from the tool's own local logs.
public struct AITokenUsage: Sendable, Equatable {
    public struct Counts: Sendable, Equatable {
        public var input: Int
        public var output: Int
        public var cacheRead: Int
        public var cacheWrite: Int
        public var reasoning: Int

        public var total: Int {
            input + output + cacheRead + cacheWrite + reasoning
        }

        public var isEmpty: Bool {
            total == 0
        }

        public init(
            input: Int = 0,
            output: Int = 0,
            cacheRead: Int = 0,
            cacheWrite: Int = 0,
            reasoning: Int = 0
        ) {
            self.input = input
            self.output = output
            self.cacheRead = cacheRead
            self.cacheWrite = cacheWrite
            self.reasoning = reasoning
        }

        public mutating func add(_ other: Counts) {
            input += other.input
            output += other.output
            cacheRead += other.cacheRead
            cacheWrite += other.cacheWrite
            reasoning += other.reasoning
        }

        public func adding(_ other: Counts) -> Counts {
            var counts = self
            counts.add(other)
            return counts
        }
    }

    public struct Tool: Sendable, Equatable, Identifiable {
        public var kind: AIToolKind
        public var counts: Counts

        public var id: AIToolKind {
            kind
        }

        public init(kind: AIToolKind, counts: Counts) {
            self.kind = kind
            self.counts = counts
        }
    }

    public var total: Counts
    public var tools: [Tool]
    public var updatedAt: Date

    /// The short text shown in the Metrics Bar, e.g. `141.9M`.
    public var barLabel: String {
        total.total.formattedTokenCount
    }

    public init(tools: [Tool], updatedAt: Date) {
        let nonEmpty = tools.filter { !$0.counts.isEmpty }.sorted { lhs, rhs in
            if lhs.counts.total != rhs.counts.total {
                return lhs.counts.total > rhs.counts.total
            }
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
        self.tools = nonEmpty
        self.total = nonEmpty.reduce(into: Counts()) { counts, tool in
            counts.add(tool.counts)
        }
        self.updatedAt = updatedAt
    }
}
