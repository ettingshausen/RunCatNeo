/*
 FileSliceClient.swift
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

/// Reads the tail of a file starting at a byte offset, for append-only logs.
public struct FileSliceClient: DependencyClient {
    public var read: @Sendable (URL, UInt64) throws -> Data

    public static let liveValue = Self(
        read: { url, offset in
            let handle = try FileHandle(forReadingFrom: url)
            defer {
                try? handle.close()
            }
            if offset > 0 {
                try handle.seek(toOffset: offset)
            }
            return handle.readDataToEndOfFile()
        }
    )

    public static let testValue = Self(
        read: { _, _ in Data() }
    )
}
