/*
 AITokenUsageService.swift
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

/// Reads today's token usage of Claude Code, ZCode and Codex CLI from their
/// own local logs — no script, no network — and publishes it as a metric.
struct AITokenUsageService {
    /// Token counts move one agent turn at a time; scanning every 15 seconds
    /// is responsive while staying cheap thanks to the incremental caches.
    static let refreshInterval: Duration = .seconds(15)

    private let appStateClient: AppStateClient
    private let dateClient: DateClient
    private let fileManagerClient: FileManagerClient
    private let fileSliceClient: FileSliceClient
    private let sqliteClient: SQLiteClient
    private let userDefaultsRepository: UserDefaultsRepository

    init(_ appDependencies: AppDependencies) {
        self.appStateClient = appDependencies.appStateClient
        self.dateClient = appDependencies.dateClient
        self.fileManagerClient = appDependencies.fileManagerClient
        self.fileSliceClient = appDependencies.fileSliceClient
        self.sqliteClient = appDependencies.sqliteClient
        self.userDefaultsRepository = .init(appDependencies.userDefaultsClient)
    }

    func startMonitoring() {
        guard appStateClient.withLock(\.aiTokenUsageObserver) == nil else {
            return
        }
        let scanner = AITokenUsageScanner(
            fileManagerClient: fileManagerClient,
            fileSliceClient: fileSliceClient,
            sqliteClient: sqliteClient
        )
        let dateClient = self.dateClient
        let appStateClient = self.appStateClient
        let task = Task<Void, Never> {
            var scanner = scanner
            while !Task.isCancelled {
                let usage = scanner.scan(now: dateClient.now())
                appStateClient.send(\.metrics, default: .init()) { metrics in
                    metrics.aiTokenUsage = usage
                }
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
        appStateClient.withLock {
            $0.aiTokenUsageObserver = task
        }
    }

    func stopMonitoring() {
        appStateClient.withLock {
            $0.aiTokenUsageObserver?.cancel()
            $0.aiTokenUsageObserver = nil
        }
        appStateClient.send(\.metrics, default: .init()) { metrics in
            metrics.aiTokenUsage = nil
        }
    }
}
