/*
 TouchBarStockBrightness.swift
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

/// The stock indicator brightness. One definition shared by the settings
/// slider and the Touch Bar's brightness page, so both behave identically.
public enum TouchBarStockBrightness {
    public static let defaultsKey = "TouchBarStockIndicatorBrightness"
    public static let minimum = 0.7
    public static let maximum = 1.5
    public static let `default` = 1.0
    public static let step = 0.05

    public static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return `default` }
        return min(max(value, minimum), maximum)
    }

    /// Rounds to the slider's step so a drag lands on the same values the
    /// settings slider offers.
    public static func rounded(_ value: Double) -> Double {
        let steps = (clamp(value) - minimum) / step
        return clamp(minimum + steps.rounded() * step)
    }
}
