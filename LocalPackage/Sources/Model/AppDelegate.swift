/*
 AppDelegate.swift
 Model

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

import AppKit
import DataSource

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appDependencies = AppDependencies.shared
    private var touchBarMetricsService: TouchBarMetricsService?
    private var stockService: StockService?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let appStateClient = appDependencies.appStateClient
        appStateClient.withLock {
            $0.name = Bundle.main.bundleDisplayName
            $0.version = Bundle.main.bundleVersion
            $0.subscriptionGroupID = Bundle.main.subscriptionGroupID
        }
        let logService = LogService(appDependencies)
        logService.bootstrap()
        let nsWorkspaceClient = appDependencies.nsWorkspaceClient
        let systemInfoObserverClient = appDependencies.systemInfoObserverClient
        let userDefaultsRepository = UserDefaultsRepository(appDependencies.userDefaultsClient)
        let customMetricsService = CustomMetricsService(appDependencies)
        let systemMetricsService = SystemMetricsService(appDependencies)
        let keyboardBatteryService = KeyboardBatteryService(appDependencies)
        let aiTokenUsageService = AITokenUsageService(appDependencies)
        let runnerService = RunnerService(appDependencies)
        let touchBarMetricsService = TouchBarMetricsService(appDependencies)
        self.touchBarMetricsService = touchBarMetricsService
        let stockService = StockService(appDependencies)
        self.stockService = stockService
        Task {
            await withTaskGroup { group in
                group.addTask {
                    let publisher = nsWorkspaceClient.publisher(NSWorkspace.willSleepNotification)
                    for await _ in publisher.values {
                        customMetricsService.stopMonitoring()
                        systemMetricsService.stopMonitoring()
                        keyboardBatteryService.stopMonitoring()
                        aiTokenUsageService.stopMonitoring()
                    }
                }
                group.addTask {
                    let publisher = nsWorkspaceClient.publisher(NSWorkspace.didWakeNotification)
                    for await _ in publisher.values {
                        customMetricsService.startMonitoring()
                        systemMetricsService.startMonitoring()
                        if userDefaultsRepository.keyboardBatteryConfiguration.isEnabled {
                            keyboardBatteryService.startMonitoring()
                        }
                        if userDefaultsRepository.aiTokenUsageConfiguration.isEnabled {
                            aiTokenUsageService.startMonitoring()
                        }
                    }
                }
                group.addTask {
                    let stream = systemInfoObserverClient.systemInfoStream()
                    for await value in stream {
                        systemMetricsService.updateMetrics(from: value)
                        runnerService.updateRunnerSpeed(from: value.cpuInfo)
                    }
                }
                group.addTask {
                    let stream = keyboardBatteryService.observe()
                    for await infos in stream {
                        keyboardBatteryService.updateMetrics(from: infos)
                    }
                }
            }
        }
        logService.notice(.launchApp)
        customMetricsService.startMonitoring()
        systemMetricsService.startMonitoring()
        if userDefaultsRepository.keyboardBatteryConfiguration.isEnabled {
            keyboardBatteryService.startMonitoring()
            if !keyboardBatteryService.isAccessGranted() {
                // Makes the app appear in the Input Monitoring list so the user
                // can grant it; a denied grant would otherwise look like a bug.
                keyboardBatteryService.requestAccess()
            }
        }
        if userDefaultsRepository.aiTokenUsageConfiguration.isEnabled {
            aiTokenUsageService.startMonitoring()
        }
        do {
            try runnerService.setup()
        } catch {
            logService.critical(.setupFailed(error))
        }
        touchBarMetricsService.start()
        stockService.start()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        CustomMetricsService(appDependencies).stopMonitoring()
        SystemMetricsService(appDependencies).stopMonitoring()
        KeyboardBatteryService(appDependencies).stopMonitoring()
        AITokenUsageService(appDependencies).stopMonitoring()
        touchBarMetricsService?.stop()
        stockService?.stop()
    }
}
