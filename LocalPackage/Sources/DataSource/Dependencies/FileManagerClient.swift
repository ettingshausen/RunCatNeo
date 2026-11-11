/*
 FileManagerClient.swift
 DataSource

 Created by Takuto Nakamura on 2026/05/05.
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

import Foundation

public struct FileManagerClient: DependencyClient {
    public struct FileInfo: Sendable, Equatable {
        public var size: Int64
        public var modificationDate: Date

        public init(size: Int64, modificationDate: Date) {
            self.size = size
            self.modificationDate = modificationDate
        }
    }

    public var urls: @Sendable (FileManager.SearchPathDirectory, FileManager.SearchPathDomainMask) -> [URL]
    public var fileExists: @Sendable (String) -> Bool
    public var createDirectory: @Sendable (URL, Bool) throws -> Void
    public var removeItem: @Sendable (URL) throws -> Void
    public var homeDirectory: @Sendable () -> URL
    public var fileURLs: @Sendable (URL, String) -> [URL]
    public var fileInfo: @Sendable (URL) -> FileInfo?

    public static let liveValue = Self(
        urls: { FileManager.default.urls(for: $0, in: $1) },
        fileExists: { FileManager.default.fileExists(atPath: $0) },
        createDirectory: { try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: $1) },
        removeItem: { try FileManager.default.removeItem(at: $0) },
        homeDirectory: { FileManager.default.homeDirectoryForCurrentUser },
        fileURLs: { directory, pathExtension in
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
            var urls = [URL]()
            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension == pathExtension else { continue }
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                if values?.isRegularFile == true {
                    urls.append(url)
                }
            }
            return urls
        },
        fileInfo: { url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            guard let size = values?.fileSize, let date = values?.contentModificationDate else {
                return nil
            }
            return FileInfo(size: Int64(size), modificationDate: date)
        }
    )

    public static let testValue = Self(
        urls: { _, _ in [URL(filePath: "/Users/user/Library/Application Support/")] },
        fileExists: { _ in false },
        createDirectory: { _, _ in },
        removeItem: { _ in },
        homeDirectory: { URL(filePath: "/Users/user") },
        fileURLs: { _, _ in [] },
        fileInfo: { _ in nil }
    )
}
