/*
 AITokenUsageScanner.swift
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

/// Turns the local logs of the supported AI tools into one day of usage.
/// A scanner instance holds per-file incremental state, so one instance must
/// own a whole run; the service creates a fresh one each monitoring cycle and
/// resets it whenever the tracked day rolls over.
struct AITokenUsageScanner {
    private struct LogEntry {
        var offset: UInt64 = 0
        var carryover = Data()
        var fileInfo: FileManagerClient.FileInfo?
        var lastTotalKey: [Int64]?
    }

    /// Deduplicates Claude Code usage records the way Tokei does: an exact
    /// `(message id, request id)` match wins, a replayed request of the same
    /// message merges into its sidechain sibling, and the larger total wins.
    private struct ClaudeEventDeduper {
        private var selected = [AITokenUsageParser.Event]()
        private var exact = [String: Int]()
        private var byMessage = [String: [Int]]()

        var counts: AITokenUsage.Counts {
            selected.reduce(into: AITokenUsage.Counts()) { counts, event in
                counts.add(event.counts)
            }
        }

        mutating func merge(_ newEvents: [AITokenUsageParser.Event]) {
            for event in newEvents {
                mergeOne(event)
            }
        }

        private mutating func mergeOne(_ event: AITokenUsageParser.Event) {
            var index: Int?
            var exactKey: String?
            if let messageID = event.messageID {
                exactKey = "\(messageID)\u{0}\(event.requestID ?? "")"
                index = exact[exactKey!]
                if index == nil, let candidates = byMessage[messageID] {
                    index = candidates.first { candidate in
                        event.isSidechain || selected[candidate].isSidechain
                    }
                }
            }
            if let index {
                if prefer(event, over: selected[index]) {
                    selected[index] = event
                }
                return
            }
            selected.append(event)
            if let exactKey {
                exact[exactKey] = selected.count - 1
            }
            if let messageID = event.messageID {
                byMessage[messageID, default: []].append(selected.count - 1)
            }
        }

        private func prefer(_ candidate: AITokenUsageParser.Event, over existing: AITokenUsageParser.Event) -> Bool {
            if candidate.isSidechain != existing.isSidechain {
                return existing.isSidechain
            }
            return candidate.counts.total > existing.counts.total
        }
    }

    private let fileManagerClient: FileManagerClient
    private let fileSliceClient: FileSliceClient
    private let sqliteClient: SQLiteClient
    private let calendar: Calendar

    private var claudeEntries = [URL: LogEntry]()
    private var codexEntries = [URL: LogEntry]()
    private var claudeDeduper = ClaudeEventDeduper()
    private var zcodeCache: (signature: String, counts: AITokenUsage.Counts)?
    private var lastTodayStart: Date?

    init(
        fileManagerClient: FileManagerClient,
        fileSliceClient: FileSliceClient,
        sqliteClient: SQLiteClient,
        calendar: Calendar = .current
    ) {
        self.fileManagerClient = fileManagerClient
        self.fileSliceClient = fileSliceClient
        self.sqliteClient = sqliteClient
        self.calendar = calendar
    }

    mutating func scan(now: Date) -> AITokenUsage {
        let todayStart = calendar.startOfDay(for: now)
        if lastTodayStart != todayStart {
            claudeEntries = [:]
            codexEntries = [:]
            claudeDeduper = ClaudeEventDeduper()
            zcodeCache = nil
            lastTodayStart = todayStart
        }
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart.addingTimeInterval(86400)
        let tools = [
            AITokenUsage.Tool(
                kind: .claudeCode,
                counts: scanClaudeCode(todayStart: todayStart, nextDayStart: nextDayStart)
            ),
            AITokenUsage.Tool(
                kind: .zcode,
                counts: scanZCode(todayStart: todayStart, nextDayStart: nextDayStart)
            ),
            AITokenUsage.Tool(
                kind: .codex,
                counts: scanCodex(todayStart: todayStart, nextDayStart: nextDayStart)
            ),
        ]
        return AITokenUsage(tools: tools, updatedAt: now)
    }

    // MARK: - Claude Code

    private mutating func scanClaudeCode(todayStart: Date, nextDayStart: Date) -> AITokenUsage.Counts {
        let root = fileManagerClient.homeDirectory().appending(path: ".claude/projects")
        let urls = fileManagerClient.fileURLs(root, "jsonl")
        var activeURLs = Set<URL>()
        for url in urls {
            // Any event dated today is appended today, so its file was
            // modified today; this filter keeps the scan off the old 400MB.
            guard let info = fileManagerClient.fileInfo(url),
                  info.modificationDate >= todayStart else {
                continue
            }
            activeURLs.insert(url)
            var entry = claudeEntries[url] ?? LogEntry()
            if let previous = entry.fileInfo, previous.size > info.size {
                entry = LogEntry()
            }
            let appended = (try? fileSliceClient.read(url, entry.offset)) ?? Data()
            let (lines, consumed, carryover) = AITokenUsageParser.completeLines(
                from: appended,
                carryover: entry.carryover
            )
            entry.offset += UInt64(consumed)
            entry.carryover = carryover
            entry.fileInfo = info
            let events = lines.compactMap(AITokenUsageParser.claudeEvent(from:)).filter { event in
                guard let timestamp = event.timestamp else { return true }
                return timestamp >= todayStart && timestamp < nextDayStart
            }
            if !events.isEmpty {
                claudeDeduper.merge(events)
            }
            claudeEntries[url] = entry
        }
        claudeEntries = claudeEntries.filter { activeURLs.contains($0.key) }
        return claudeDeduper.counts
    }

    // MARK: - ZCode

    private mutating func scanZCode(todayStart: Date, nextDayStart: Date) -> AITokenUsage.Counts {
        let databaseDirectory = fileManagerClient.homeDirectory().appending(path: ".zcode/cli/db")
        let databaseURL = databaseDirectory.appending(path: "db.sqlite")
        let databasePath = databaseURL.path(percentEncoded: false)
        guard fileManagerClient.fileExists(databasePath) else {
            return .init()
        }
        // WAL writes do not always touch the main database file, so track both.
        let signature = [databaseURL, databaseDirectory.appending(path: "db.sqlite-wal")].map { url -> String in
            guard let info = fileManagerClient.fileInfo(url) else { return "missing" }
            return "\(info.size)|\(info.modificationDate.timeIntervalSince1970)"
        }.joined(separator: "|")
        if let cache = zcodeCache, cache.signature == signature {
            return cache.counts
        }
        let startMilliseconds = Int64(todayStart.timeIntervalSince1970 * 1000)
        let sql = """
            SELECT input_tokens, output_tokens, cache_creation_input_tokens, \
            cache_read_input_tokens, completed_at, started_at
            FROM model_usage
            WHERE completed_at >= \(startMilliseconds) OR started_at >= \(startMilliseconds)
            """
        var counts = AITokenUsage.Counts()
        if let rows = try? sqliteClient.query(databasePath, sql) {
            for row in rows where row.count == 6 {
                let timestampMilliseconds = row[4] ?? row[5]
                guard let timestampMilliseconds, timestampMilliseconds > 0 else {
                    continue
                }
                let date = Date(timeIntervalSince1970: Double(timestampMilliseconds) / 1000)
                guard date >= todayStart, date < nextDayStart else {
                    continue
                }
                let input = row[0] ?? 0
                let output = row[1] ?? 0
                let cacheWrite = row[2] ?? 0
                let cacheRead = row[3] ?? 0
                // model_usage stores cached input inside input_tokens; only
                // the fresh part counts as input, exactly like Tokei.
                counts.input += Int(max(input - cacheWrite - cacheRead, 0))
                counts.output += Int(output)
                counts.cacheWrite += Int(cacheWrite)
                counts.cacheRead += Int(cacheRead)
            }
        }
        zcodeCache = (signature, counts)
        return counts
    }

    // MARK: - Codex CLI

    private mutating func scanCodex(todayStart: Date, nextDayStart: Date) -> AITokenUsage.Counts {
        let root = fileManagerClient.homeDirectory().appending(path: ".codex/sessions")
        let urls = fileManagerClient.fileURLs(root, "jsonl")
        var counts = AITokenUsage.Counts()
        var activeURLs = Set<URL>()
        for url in urls {
            guard let info = fileManagerClient.fileInfo(url),
                  info.modificationDate >= todayStart else {
                continue
            }
            activeURLs.insert(url)
            var entry = codexEntries[url] ?? LogEntry()
            if let previous = entry.fileInfo, previous.size > info.size {
                entry = LogEntry()
            }
            let appended = (try? fileSliceClient.read(url, entry.offset)) ?? Data()
            let (lines, consumed, carryover) = AITokenUsageParser.completeLines(
                from: appended,
                carryover: entry.carryover
            )
            entry.offset += UInt64(consumed)
            entry.carryover = carryover
            entry.fileInfo = info
            for line in lines {
                guard let parsed = AITokenUsageParser.codexEvent(from: line) else {
                    continue
                }
                if parsed.totalKey == entry.lastTotalKey {
                    continue
                }
                entry.lastTotalKey = parsed.totalKey
                if let timestamp = parsed.event.timestamp {
                    if timestamp >= todayStart && timestamp < nextDayStart {
                        counts.add(parsed.event.counts)
                    }
                } else {
                    counts.add(parsed.event.counts)
                }
            }
            codexEntries[url] = entry
        }
        codexEntries = codexEntries.filter { activeURLs.contains($0.key) }
        return counts
    }
}
