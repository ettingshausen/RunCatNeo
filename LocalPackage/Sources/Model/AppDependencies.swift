/*
 AppDependencies.swift
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

import DataSource
import SwiftUI

public struct AppDependencies: Sendable {
    public var appStateClient = AppStateClient.liveValue
    public var dataClient = DataClient.liveValue
    public var dateClient = DateClient.liveValue
    public var fileManagerClient = FileManagerClient.liveValue
    public var fileSliceClient = FileSliceClient.liveValue
    public var fileWatcherClient = FileWatcherClient.liveValue
    public var loggingSystemClient = LoggingSystemClient.liveValue
    public var nsAppClient = NSAppClient.liveValue
    public var nsWorkspaceClient = NSWorkspaceClient.liveValue
    public var keyboardBatteryObserverClient = KeyboardBatteryObserverClient.liveValue
    public var smAppServiceClient = SMAppServiceClient.liveValue
    public var smcClient = SMCClient.liveValue
    public var sqliteClient = SQLiteClient.liveValue
    public var stockClient = StockClient.liveValue
    public var systemInfoObserverClient = SystemInfoObserverClient.liveValue
    public var touchBarClient = TouchBarClient.liveValue
    public var urlClient = URLClient.liveValue
    public var userDefaultsClient = UserDefaultsClient.liveValue
    public var uuidClient = UUIDClient.liveValue

    public static let shared = AppDependencies()
}

extension EnvironmentValues {
    @Entry public var appDependencies = AppDependencies.shared
}

extension AppDependencies {
    public static func testDependencies(
        appStateClient: AppStateClient = .testValue,
        dataClient: DataClient = .testValue,
        dateClient: DateClient = .testValue,
        fileManagerClient: FileManagerClient = .testValue,
        fileSliceClient: FileSliceClient = .testValue,
        fileWatcherClient: FileWatcherClient = .testValue,
        loggingSystemClient: LoggingSystemClient = .testValue,
        nsAppClient: NSAppClient = .testValue,
        nsWorkspaceClient: NSWorkspaceClient = .testValue,
        keyboardBatteryObserverClient: KeyboardBatteryObserverClient = .testValue,
        smAppServiceClient: SMAppServiceClient = .testValue,
        smcClient: SMCClient = .testValue,
        sqliteClient: SQLiteClient = .testValue,
        stockClient: StockClient = .testValue,
        systemInfoObserverClient: SystemInfoObserverClient = .testValue,
        touchBarClient: TouchBarClient = .testValue,
        urlClient: URLClient = .testValue,
        userDefaultsClient: UserDefaultsClient = .testValue,
        uuidClient: UUIDClient = .testValue
    ) -> AppDependencies {
        AppDependencies(
            appStateClient: appStateClient,
            dataClient: dataClient,
            dateClient: dateClient,
            fileManagerClient: fileManagerClient,
            fileSliceClient: fileSliceClient,
            fileWatcherClient: fileWatcherClient,
            loggingSystemClient: loggingSystemClient,
            nsAppClient: nsAppClient,
            nsWorkspaceClient: nsWorkspaceClient,
            keyboardBatteryObserverClient: keyboardBatteryObserverClient,
            smAppServiceClient: smAppServiceClient,
            smcClient: smcClient,
            sqliteClient: sqliteClient,
            stockClient: stockClient,
            systemInfoObserverClient: systemInfoObserverClient,
            touchBarClient: touchBarClient,
            urlClient: urlClient,
            userDefaultsClient: userDefaultsClient,
            uuidClient: uuidClient
        )
    }
}
