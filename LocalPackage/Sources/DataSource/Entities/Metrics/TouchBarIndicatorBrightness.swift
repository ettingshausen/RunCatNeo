/*
 TouchBarIndicatorBrightness.swift
 DataSource

 Created by ettingshausen on 2026/11/17.
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

/// The luminance factor of the Touch Bar's neutral content (indicator text
/// and icons). Stock colors are deliberately excluded: up and down keep the
/// market convention red/green at their own brightness setting.
public enum TouchBarIndicatorBrightness {
    public static let defaultsKey = "TouchBarIndicatorBrightness"
    public static let minimum = 0.3
    public static let maximum = 1.0
    public static let `default` = 1.0

    public static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return `default` }
        return min(max(value, minimum), maximum)
    }

    /// Steps the value one notch, used by the bar's brightness page.
    public static let step = 0.05
}
