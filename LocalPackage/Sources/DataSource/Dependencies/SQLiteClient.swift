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

    public var query: @Sendable (String, String) throws -> [[Int64?]]

    public static let liveValue = Self(
        query: { databasePath, sql in
            var database: OpaquePointer?
            guard sqlite3_open_v2(databasePath, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
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
        query: { _, _ in [] }
    )
}
