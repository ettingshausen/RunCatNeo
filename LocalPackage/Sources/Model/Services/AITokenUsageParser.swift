/*
 AITokenUsageParser.swift
 Model

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

import DataSource
import Foundation

/// Pure parsers for the append-only logs of Claude Code and Codex CLI.
/// Byte-to-event bookkeeping (offsets, partial lines, dedupe state) lives in
/// `AITokenUsageScanner`; these functions only turn one line into one event.
enum AITokenUsageParser {
    /// One usage record from a transcript or rollout line.
    struct Event: Equatable, Sendable {
        var timestamp: Date?
        var messageID: String?
        var requestID: String?
        var isSidechain: Bool
        var counts: AITokenUsage.Counts
    }

    /// `ISO8601DateFormatter` is not `Sendable`; the formatters are only ever
    /// touched from a single scanner run, so the box is safe to share.
    private struct TimestampFormatters: @unchecked Sendable {
        static let shared = TimestampFormatters()
        let fractional: ISO8601DateFormatter
        let plain: ISO8601DateFormatter

        private init() {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            self.fractional = fractional
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            self.plain = plain
        }
    }

    static func date(from timestamp: String) -> Date? {
        let formatters = TimestampFormatters.shared
        return formatters.fractional.date(from: timestamp) ?? formatters.plain.date(from: timestamp)
    }

    private static func positiveInt(_ value: Any?) -> Int {
        guard let number = value as? NSNumber else {
            return 0
        }
        return max(number.intValue, 0)
    }

    private static func nonNegativeInt64(_ value: Any?) -> Int64 {
        guard let number = value as? NSNumber else {
            return 0
        }
        return max(number.int64Value, 0)
    }

    /// Splits appended bytes into complete lines plus the trailing partial line.
    static func completeLines(
        from appended: Data,
        carryover: Data
    ) -> (lines: [Data], consumed: Int, carryover: Data) {
        let buffer = carryover + appended
        var lines = [Data]()
        var searchStart = buffer.startIndex
        while let newline = buffer[searchStart...].firstIndex(of: UInt8(ascii: "\n")) {
            var line = buffer[searchStart..<newline]
            if line.last == UInt8(ascii: "\r") {
                line = line.dropLast()
            }
            if !line.isEmpty {
                lines.append(Data(line))
            }
            searchStart = buffer.index(after: newline)
        }
        let consumed = buffer.distance(from: buffer.startIndex, to: searchStart)
        let rest = buffer[searchStart...]
        return (lines, consumed, Data(rest))
    }

    // MARK: - Claude Code

    /// `~/.claude/projects/**/*.jsonl`, assistant lines carry `message.usage`.
    /// Token buckets mirror the Anthropic API: `input_tokens` excludes cached
    /// input, so the day total is input + output + cacheRead + cacheWrite.
    /// Claude Code only writes main-turn replies as assistant messages; the
    /// usage of side calls (web search, compaction) appears in cost-state
    /// lines that this parser does not read, so day totals can be slightly
    /// lower than Tokei's.
    static func claudeEvent(from line: Data) -> Event? {
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              object["type"] as? String == "assistant",
              let message = object["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any] else {
            return nil
        }
        let counts = AITokenUsage.Counts(
            input: positiveInt(usage["input_tokens"]),
            output: positiveInt(usage["output_tokens"]),
            cacheRead: positiveInt(usage["cache_read_input_tokens"]),
            cacheWrite: positiveInt(usage["cache_creation_input_tokens"])
        )
        guard !counts.isEmpty else {
            return nil
        }
        return Event(
            timestamp: (object["timestamp"] as? String).flatMap(date(from:)),
            messageID: message["id"] as? String,
            requestID: object["requestId"] as? String,
            isSidechain: object["isSidechain"] as? Bool ?? false,
            counts: counts
        )
    }

    // MARK: - Codex CLI

    /// `~/.codex/sessions/**/rollout-*.jsonl` token_count events. Returns the
    /// event plus the cumulative snapshot key the caller deduplicates on:
    /// Codex repeats the same cumulative total across events, and repeats
    /// `last_token_usage` along with it, so counting both would overstate.
    /// Output already contains reasoning, so `reasoning` stays zero here.
    static func codexEvent(from line: Data) -> (event: Event, totalKey: [Int64])? {
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              object["type"] as? String == "event_msg",
              let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any] else {
            return nil
        }
        let last = info["last_token_usage"] as? [String: Any] ?? [:]
        let counts = AITokenUsage.Counts(
            input: positiveInt(last["input_tokens"]),
            output: positiveInt(last["output_tokens"]),
            cacheRead: positiveInt(last["cached_input_tokens"])
        )
        guard !counts.isEmpty else {
            return nil
        }
        let total = info["total_token_usage"] as? [String: Any]
        let totalKey = [
            nonNegativeInt64(total?["input_tokens"]),
            nonNegativeInt64(total?["cached_input_tokens"]),
            nonNegativeInt64(total?["output_tokens"]),
            nonNegativeInt64(total?["reasoning_output_tokens"]),
        ]
        let event = Event(
            timestamp: (object["timestamp"] as? String).flatMap(date(from:)),
            messageID: nil,
            requestID: nil,
            isSidechain: false,
            counts: counts
        )
        return (event, totalKey)
    }
}
