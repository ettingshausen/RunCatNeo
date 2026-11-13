/*
 TouchBarIndicator.swift
 DataSource

 Created by ettingshausen on 2026/11/12.
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

/// One metric shown on the Touch Bar. `systemIcon` is an SF Symbol name and
/// `primaryText`/`secondaryText` are pre-formatted labels; the network
/// indicator carries both its upload and download lines.
public struct TouchBarIndicator: Sendable, Equatable {
    /// Which configured item this indicator came from. Stacks reference items
    /// by this identity rather than by position in the rendered array.
    public let member: TouchBarMember
    public let systemIcon: String
    public let primaryText: String
    public let secondaryText: String?

    public init(
        member: TouchBarMember,
        systemIcon: String,
        primaryText: String,
        secondaryText: String? = nil
    ) {
        self.member = member
        self.systemIcon = systemIcon
        self.primaryText = primaryText
        self.secondaryText = secondaryText
    }
}
