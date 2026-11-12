/*
 TouchBarConfiguration.swift
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

public enum TouchBarDisplayMode: String, Codable, Sendable, CaseIterable {
    // The metrics bar stays collapsed into the Control Strip anchor icon and
    // only expands when the user taps the anchor.
    case anchorOnly
    // The metrics bar is presented system-modally at all times.
    case alwaysExpanded
    // The metrics bar expands unless the frontmost app is excluded; excluded
    // apps (typically ones with their own Touch Bar content) collapse it.
    case smart
}

/// A metric that can be shown on the Touch Bar. Deliberately a separate list
/// from the menu bar metrics bar's own visibility flags: the two surfaces are
/// configured independently.
public enum TouchBarMetric: String, Codable, Sendable, CaseIterable {
    case cpu
    case memory
    case storage
    case battery
    case network
    case fan
    case keyboardBattery
    case aiTokenUsage
}

public struct TouchBarConfiguration: Codable, Sendable, Equatable {
    public var mode: TouchBarDisplayMode
    public var excludedBundleIdentifiers: [String]
    public var visibleMetrics: Set<TouchBarMetric>
    public var visibleCustomMetricsSourceIDs: Set<UUID>

    public static let `default` = Self(
        mode: .smart,
        excludedBundleIdentifiers: [],
        visibleMetrics: Set(TouchBarMetric.allCases),
        visibleCustomMetricsSourceIDs: []
    )

    public init(
        mode: TouchBarDisplayMode,
        excludedBundleIdentifiers: [String],
        visibleMetrics: Set<TouchBarMetric> = Set(TouchBarMetric.allCases),
        visibleCustomMetricsSourceIDs: Set<UUID> = []
    ) {
        self.mode = mode
        self.excludedBundleIdentifiers = excludedBundleIdentifiers
        self.visibleMetrics = visibleMetrics
        self.visibleCustomMetricsSourceIDs = visibleCustomMetricsSourceIDs
    }

    public func shows(_ metric: TouchBarMetric) -> Bool {
        visibleMetrics.contains(metric)
    }

    public func showsCustomMetrics(of id: UUID) -> Bool {
        visibleCustomMetricsSourceIDs.contains(id)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(TouchBarDisplayMode.self, forKey: .mode) ?? .smart
        excludedBundleIdentifiers = try container.decodeIfPresent([String].self, forKey: .excludedBundleIdentifiers) ?? []
        // Configurations written before per-metric visibility existed showed
        // every metric, so an absent key must decode to the full set.
        visibleMetrics = try container.decodeIfPresent(Set<TouchBarMetric>.self, forKey: .visibleMetrics)
            ?? Set(TouchBarMetric.allCases)
        visibleCustomMetricsSourceIDs = try container.decodeIfPresent(
            Set<UUID>.self,
            forKey: .visibleCustomMetricsSourceIDs
        ) ?? []
    }
}
