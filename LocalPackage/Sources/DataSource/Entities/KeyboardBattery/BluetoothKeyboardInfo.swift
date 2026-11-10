/*
 BluetoothKeyboardInfo.swift
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

public struct BluetoothKeyboardInfo: Codable, Sendable, Equatable, Identifiable {
    public enum Status: String, Codable, Sendable {
        case ok
        case needsPermission
        case noReport
    }

    public var id: String
    public var name: String
    public var percent: Int?
    public var changedAt: Date?
    public var lastSeenAt: Date?
    public var status: Status

    public init(
        id: String,
        name: String,
        percent: Int? = nil,
        changedAt: Date? = nil,
        lastSeenAt: Date? = nil,
        status: Status
    ) {
        self.id = id
        self.name = name
        self.percent = percent
        self.changedAt = changedAt
        self.lastSeenAt = lastSeenAt
        self.status = status
    }
}
