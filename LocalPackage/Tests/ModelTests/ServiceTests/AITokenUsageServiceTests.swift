/*
 AITokenUsageServiceTests.swift
 ModelTests

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

import AllocatedUnfairLock
import Foundation
import Testing

@testable import DataSource
@testable import Model

struct AITokenUsageServiceTests {
    private let now = Date()
    private let fixtureURL = URL(filePath: "/Users/user/.claude/projects/project/session.jsonl")

    private var todayStart: Date {
        Calendar.current.startOfDay(for: now)
    }

    private func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func milliseconds(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000)
    }

    private func claudeLine(
        input: Int,
        output: Int = 0,
        cacheRead: Int = 0,
        cacheWrite: Int = 0,
        id: String? = "msg_1",
        request: String = "req_1",
        timestamp: Date? = nil,
        isSidechain: Bool = false,
        type: String = "assistant"
    ) -> String {
        let usage = """
            {"input_tokens": \(input), "output_tokens": \(output), \
            "cache_read_input_tokens": \(cacheRead), "cache_creation_input_tokens": \(cacheWrite)}
            """
        let quotedID = id.map { "\"" + $0 + "\"" } ?? "null"
        let message = """
            "message": {"id": \(quotedID), "model": "test-model", "usage": \(usage)}
            """
        let sidechain = isSidechain ? ", \"isSidechain\": true" : ""
        let stamp = ", \"timestamp\": \"\(iso8601(timestamp ?? now))\""
        return """
            {"type": "\(type)", "requestId": "\(request)"\(stamp)\(sidechain), \(message)}
            """
    }

    // MARK: - Parser

    @Test
    func claudeEvent_parses_assistant_usage_line() throws {
        let timestamp = Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down) - 30)
        let event = try #require(AITokenUsageParser.claudeEvent(from: Data(claudeLine(
            input: 100,
            output: 20,
            cacheRead: 50,
            cacheWrite: 30,
            timestamp: timestamp
        ).utf8)))
        #expect(event.messageID == "msg_1")
        #expect(event.requestID == "req_1")
        #expect(event.timestamp == timestamp)
        #expect(event.counts == AITokenUsage.Counts(input: 100, output: 20, cacheRead: 50, cacheWrite: 30))
    }

    @Test
    func claudeEvent_ignores_non_assistant_and_usage_free_lines() {
        #expect(AITokenUsageParser.claudeEvent(from: Data(claudeLine(input: 10, type: "user").utf8)) == nil)
        #expect(AITokenUsageParser.claudeEvent(from: Data("not json".utf8)) == nil)
    }

    @Test
    func completeLines_returns_only_whole_lines_and_keeps_the_tail() {
        let (lines, consumed, carryover) = AITokenUsageParser.completeLines(
            from: Data("first\nseco".utf8),
            carryover: Data()
        )
        #expect(lines.count == 1)
        #expect(consumed == 6)
        #expect(carryover == Data("seco".utf8))
        let (nextLines, nextConsumed, nextCarryover) = AITokenUsageParser.completeLines(
            from: Data("nd\n".utf8),
            carryover: carryover
        )
        #expect(nextLines == [Data("second".utf8)])
        #expect(nextConsumed == 7)
        #expect(nextCarryover.isEmpty)
    }

    @Test
    func codexEvent_parses_token_count_and_returns_total_key() throws {
        let line = """
            {"timestamp": "\(iso8601(now))", "type": "event_msg", "payload": {"type": "token_count", \
            "info": {"last_token_usage": {"input_tokens": 100, "cached_input_tokens": 50, "output_tokens": 10}, \
            "total_token_usage": {"input_tokens": 200, "cached_input_tokens": 50, "output_tokens": 30, \
            "reasoning_output_tokens": 5}}}}
            """
        let parsed = try #require(AITokenUsageParser.codexEvent(from: Data(line.utf8)))
        #expect(parsed.event.counts == AITokenUsage.Counts(input: 100, output: 10, cacheRead: 50))
        #expect(parsed.totalKey == [200, 50, 30, 5])
    }

    // MARK: - Scanner

    private func makeScanner(
        fileURLs: [URL],
        fileInfo: @escaping @Sendable (URL) -> FileManagerClient.FileInfo?,
        fileSlice: @escaping @Sendable (URL, UInt64) throws -> Data,
        fileExists: @escaping @Sendable (String) -> Bool = { _ in true },
        rows: @escaping @Sendable () throws -> [[Int64?]] = { [] }
    ) -> AITokenUsageScanner {
        AITokenUsageScanner(
            fileManagerClient: testDependency(of: FileManagerClient.self) {
                $0.fileURLs = { _, _ in fileURLs }
                $0.fileInfo = fileInfo
                $0.fileExists = fileExists
            },
            fileSliceClient: testDependency(of: FileSliceClient.self) {
                $0.read = fileSlice
            },
            sqliteClient: testDependency(of: SQLiteClient.self) {
                $0.query = { _, _, _ in try rows() }
            }
        )
    }

    @Test
    func scan_claude_counts_today_events_and_deduplicates() {
        let payload = Data("""
            \(claudeLine(input: 10, output: 5, id: "msg_1"))
            \(claudeLine(input: 20, output: 5, id: "msg_1"))
            \(claudeLine(input: 7, output: 1, id: "msg_2", request: "req_2"))
            \(claudeLine(input: 3, type: "user"))
            par
            """.utf8)
        var scanner = makeScanner(
            fileURLs: [fixtureURL],
            fileInfo: { [now] _ in .init(size: Int64(payload.count), modificationDate: now) },
            fileSlice: { _, _ in payload }
        )
        let usage = scanner.scan(now: now)
        // The repeated (msg_1, req_1) pair keeps the larger total: 25 + 8.
        #expect(usage.tools.first { $0.kind == .claudeCode }?.counts == AITokenUsage.Counts(input: 27, output: 6))
    }

    @Test
    func scan_claude_excludes_events_before_today_and_merges_sidechain_replays() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: todayStart)!
        let payload = Data("""
            \(claudeLine(input: 999, timestamp: yesterday))
            \(claudeLine(input: 10, id: "msg_1"))
            \(claudeLine(input: 30, id: "msg_1", request: "req_2", isSidechain: true))
            """.utf8)
        var scanner = makeScanner(
            fileURLs: [fixtureURL],
            fileInfo: { [now] _ in .init(size: Int64(payload.count), modificationDate: now) },
            fileSlice: { _, _ in payload }
        )
        let usage = scanner.scan(now: now)
        // The sidechain replay of msg_1 merges into its main-thread sibling,
        // and the main event wins the preference just like Tokei.
        #expect(usage.tools.first { $0.kind == .claudeCode }?.counts.total == 10)
    }

    @Test
    func scan_claude_resumes_from_offset_without_double_counting() {
        let base = Data("\(claudeLine(input: 10, output: 5, id: "msg_1"))\n".utf8)
        let appended = Data("\(claudeLine(input: 7, output: 1, id: "msg_2", request: "req_2"))\n".utf8)
        let baseCount = Int64(base.count)
        var scanner = makeScanner(
            fileURLs: [fixtureURL],
            fileInfo: { [now] _ in .init(size: baseCount, modificationDate: now) },
            fileSlice: { _, offset in Data(base.dropFirst(Int(offset))) }
        )
        var usage = scanner.scan(now: now)
        #expect(usage.tools.first { $0.kind == .claudeCode }?.counts.total == 15)
        usage = scanner.scan(now: now)
        #expect(usage.tools.first { $0.kind == .claudeCode }?.counts.total == 15)

        // The file grows by one event between scans.
        var grown = makeScanner(
            fileURLs: [fixtureURL],
            fileInfo: { [now] _ in .init(size: baseCount + Int64(appended.count), modificationDate: now) },
            fileSlice: { _, offset in
                if offset >= UInt64(baseCount) {
                    return Data(appended.dropFirst(Int(offset - UInt64(baseCount))))
                }
                return Data(base.dropFirst(Int(offset)))
            }
        )
        usage = grown.scan(now: now)
        #expect(usage.tools.first { $0.kind == .claudeCode }?.counts.total == 15)
        usage = grown.scan(now: now)
        #expect(usage.tools.first { $0.kind == .claudeCode }?.counts.total == 23)
    }

    @Test
    func scan_zcode_splits_cached_input_and_caches_by_signature() throws {
        let queryCalls = AllocatedUnfairLock<Int>(initialState: 0)
        var scanner = AITokenUsageScanner(
            fileManagerClient: testDependency(of: FileManagerClient.self) {
                $0.fileExists = { _ in true }
                $0.fileInfo = { [now] _ in .init(size: 1, modificationDate: now) }
            },
            fileSliceClient: .testValue,
            sqliteClient: testDependency(of: SQLiteClient.self) {
                $0.query = { _, _, _ in
                    queryCalls.withLock { $0 += 1 }
                    return [
                        [100, 10, 30, 20, milliseconds(now), milliseconds(now.addingTimeInterval(-1))],
                        [5, 1, nil, nil, nil, milliseconds(now)],
                        [999, 9, nil, nil, milliseconds(todayStart.addingTimeInterval(-600_000)), nil],
                    ]
                }
            }
        )
        // input=100 splits into fresh 50 + cacheWrite 30 + cacheRead 20; the
        // third row belongs to last week and is excluded.
        var counts = try #require(scanner.scan(now: now).tools.first { $0.kind == .zcode }?.counts)
        #expect(counts == AITokenUsage.Counts(input: 55, output: 11, cacheRead: 20, cacheWrite: 30))
        #expect(queryCalls.withLock { $0 } == 1)
        // An unchanged signature must not re-query the database.
        counts = try #require(scanner.scan(now: now).tools.first { $0.kind == .zcode }?.counts)
        #expect(counts == AITokenUsage.Counts(input: 55, output: 11, cacheRead: 20, cacheWrite: 30))
        #expect(queryCalls.withLock { $0 } == 1)
    }

    @Test
    func scan_zcode_reads_immutable_after_zcode_quits_without_sidecars() throws {
        let immutableFlags = AllocatedUnfairLock<[Bool]>(initialState: [])
        var scanner = AITokenUsageScanner(
            fileManagerClient: testDependency(of: FileManagerClient.self) {
                $0.fileExists = { _ in true }
                // Only the database exists: a clean ZCode exit deletes the -wal.
                $0.fileInfo = { [now] url in
                    url.pathExtension == "sqlite" ? .init(size: 4096, modificationDate: now) : nil
                }
            },
            fileSliceClient: .testValue,
            sqliteClient: testDependency(of: SQLiteClient.self) {
                $0.query = { _, _, isImmutable in
                    immutableFlags.withLock { $0.append(isImmutable) }
                    return [[10, 2, nil, nil, milliseconds(now), milliseconds(now)]]
                }
            }
        )
        let counts = try #require(scanner.scan(now: now).tools.first { $0.kind == .zcode }?.counts)
        #expect(counts == AITokenUsage.Counts(input: 10, output: 2))
        #expect(immutableFlags.withLock { $0 } == [true])
    }

    @Test
    func scan_zcode_falls_back_to_immutable_when_the_plain_query_fails() throws {
        var scanner = AITokenUsageScanner(
            fileManagerClient: testDependency(of: FileManagerClient.self) {
                $0.fileExists = { _ in true }
                $0.fileInfo = { [now] _ in .init(size: 1, modificationDate: now) }
            },
            fileSliceClient: .testValue,
            sqliteClient: testDependency(of: SQLiteClient.self) {
                // The -wal exists at stat time but ZCode quits before the
                // query, so the plain open fails and the immutable retry
                // against the checkpointed main file recovers the rows.
                $0.query = { _, _, isImmutable in
                    guard isImmutable else {
                        throw SQLiteClient.SQLiteError.openFailed(code: 14)
                    }
                    return [[10, 2, nil, nil, milliseconds(now), milliseconds(now)]]
                }
            }
        )
        let counts = try #require(scanner.scan(now: now).tools.first { $0.kind == .zcode }?.counts)
        #expect(counts == AITokenUsage.Counts(input: 10, output: 2))
    }

    @Test
    func scan_codex_skips_repeated_cumulative_snapshots() {
        let line: (Int, Int, Int) -> String = { input, cached, output in
            """
            {"timestamp": "\(iso8601(now))", "type": "event_msg", "payload": {"type": "token_count", \
            "info": {"last_token_usage": {"input_tokens": \(input), "cached_input_tokens": \(cached), \
            "output_tokens": \(output)}, "total_token_usage": {"input_tokens": \(input + 200), \
            "cached_input_tokens": \(cached), "output_tokens": \(output + 10), "reasoning_output_tokens": 0}}}}
            """
        }
        let payload = Data("\(line(100, 50, 10))\n\(line(100, 50, 10))\n\(line(5, 0, 2))\n".utf8)
        var scanner = makeScanner(
            fileURLs: [URL(filePath: "/Users/user/.codex/sessions/rollout-1.jsonl")],
            fileInfo: { [now] _ in .init(size: Int64(payload.count), modificationDate: now) },
            fileSlice: { _, _ in payload }
        )
        let usage = scanner.scan(now: now)
        // The repeated cumulative snapshot is skipped: 105 + 2.
        #expect(usage.tools.first { $0.kind == .codex }?.counts == AITokenUsage.Counts(input: 105, output: 12, cacheRead: 50))
    }

    @Test
    func scan_with_missing_sources_returns_empty_tools() {
        var scanner = makeScanner(
            fileURLs: [],
            fileInfo: { _ in nil },
            fileSlice: { _, _ in Data() },
            fileExists: { _ in false }
        )
        let usage = scanner.scan(now: now)
        #expect(usage.tools.isEmpty)
        #expect(usage.total.isEmpty)
    }

    // MARK: - Service

    @Test
    func startMonitoring_publishes_usage_into_metrics_and_stop_clears_it() async {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let payload = Data("\(claudeLine(input: 10, output: 5, id: "msg_1"))\n".utf8)
        let sut = AITokenUsageService(.testDependencies(
            appStateClient: .testDependency(appState),
            dateClient: testDependency(of: DateClient.self) { $0.now = { self.now } },
            fileManagerClient: testDependency(of: FileManagerClient.self) {
                $0.fileURLs = { _, _ in [self.fixtureURL] }
                $0.fileInfo = { [now] _ in .init(size: Int64(payload.count), modificationDate: now) }
            },
            fileSliceClient: testDependency(of: FileSliceClient.self) {
                $0.read = { _, _ in payload }
            }
        ))
        sut.startMonitoring()
        await waitUntil { appState.withLock(\.metrics.latestValue)?.aiTokenUsage?.total.total == 15 }
        sut.stopMonitoring()
        await waitUntil { appState.withLock(\.metrics.latestValue)?.aiTokenUsage == nil }
    }
}
