/*
 SQLiteClient.swift
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
import SQLite3

public struct SQLiteClient: DependencyClient {
    public enum SQLiteError: Error, Equatable {
        case openFailed(code: Int32)
        case prepareFailed(code: Int32)
        case stepFailed(code: Int32)
    }

    /// - Parameters:
    ///   - databasePath: Path of the database file to open.
    ///   - sql: The query to run; every column is read as an integer or nil.
    ///   - isImmutable: Opens the file with SQLite's `immutable=1` URI flag.
    ///     Required for a WAL-mode database whose writer has quit: the -wal
    ///     and -shm sidecars are deleted on a clean exit, and a read-only
    ///     connection may not rebuild the missing -wal-index, so the plain
    ///     open fails. In that state the checkpointed main file holds every
    ///     committed row, and `immutable=1` reads it without touching locks
    ///     or sidecars.
    public var query: @Sendable (String, String, _ isImmutable: Bool) throws -> [[Int64?]]

    public static let liveValue = Self(
        query: { databasePath, sql, isImmutable in
            var openPath = databasePath
            var openFlags = SQLITE_OPEN_READONLY
            if isImmutable {
                openPath = URL(fileURLWithPath: databasePath).absoluteString + "?immutable=1"
                openFlags |= SQLITE_OPEN_URI
            }
            var database: OpaquePointer?
            guard sqlite3_open_v2(openPath, &database, openFlags, nil) == SQLITE_OK else {
                let code = sqlite3_errcode(database)
                sqlite3_close_v2(database)
                throw SQLiteError.openFailed(code: code)
            }
            defer {
                sqlite3_close_v2(database)
            }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteError.prepareFailed(code: sqlite3_errcode(database))
            }
            defer {
                sqlite3_finalize(statement)
            }
            var rows = [[Int64?]]()
            while true {
                let code = sqlite3_step(statement)
                switch code {
                case SQLITE_ROW:
                    let columnCount = sqlite3_column_count(statement)
                    let row = (0..<columnCount).map { column -> Int64? in
                        sqlite3_column_type(statement, column) == SQLITE_NULL
                            ? nil
                            : sqlite3_column_int64(statement, column)
                    }
                    rows.append(row)
                case SQLITE_DONE:
                    return rows
                default:
                    throw SQLiteError.stepFailed(code: code)
                }
            }
        }
    )

    public static let testValue = Self(
        query: { _, _, _ in [] }
    )
}
