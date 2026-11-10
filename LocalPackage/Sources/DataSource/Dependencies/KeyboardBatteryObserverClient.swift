/*
 KeyboardBatteryObserverClient.swift
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

public struct KeyboardBatteryObserverClient: DependencyClient {
    public var stream: @Sendable () -> AsyncStream<[BluetoothKeyboardInfo]>
    public var currentValue: @Sendable () -> [BluetoothKeyboardInfo]
    public var startMonitoring: @Sendable () -> Void
    public var stopMonitoring: @Sendable () -> Void
    public var isAccessGranted: @Sendable () -> Bool
    public var requestAccess: @Sendable () -> Void

    public static let liveValue = Self(
        stream: { KeyboardBatteryObserver.shared.stream() },
        currentValue: { KeyboardBatteryObserver.shared.currentValue() },
        startMonitoring: { KeyboardBatteryObserver.shared.startMonitoring() },
        stopMonitoring: { KeyboardBatteryObserver.shared.stopMonitoring() },
        isAccessGranted: { KeyboardBatteryObserver.shared.isAccessGranted },
        requestAccess: { KeyboardBatteryObserver.shared.requestAccess() }
    )

    public static let testValue = Self(
        stream: { AsyncStream { $0.finish() } },
        currentValue: { [] },
        startMonitoring: {},
        stopMonitoring: {},
        isAccessGranted: { true },
        requestAccess: {}
    )
}
