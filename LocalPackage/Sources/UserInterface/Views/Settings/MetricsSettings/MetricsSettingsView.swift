/*
 MetricsSettingsView.swift
 UserInterface

 Created by Takuto Nakamura on 2026/05/23.
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
import Model
import SwiftUI
import UniformTypeIdentifiers

private let toggleColumnWidth: CGFloat = 62

struct MetricsSettingsView: View {
    @StateObject var store: MetricsSettings

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding<Bool>(
                    get: { store.showsMetricsBar },
                    asyncSet: { await store.send(.showMetricsBarToggleSwitched($0)) }
                )) {
                    Text("showMetricsBar", bundle: .module)
                }
                .sheet(isPresented: $store.showingMetricsBarNotesSheet) {
                    MetricsBarNotesView(store: store)
                }
                if store.isTouchBarHardwareAvailable {
                    Toggle(isOn: Binding<Bool>(
                        get: { store.showsMetricsBarOnTouchBar },
                        asyncSet: { await store.send(.showsMetricsBarOnTouchBarToggleSwitched($0)) }
                    )) {
                        Text("showMetricsBarOnTouchBar", bundle: .module)
                    }
                }
            } header: {
                // Machines without a Touch Bar must not see "Touch Bar" here.
                if store.isTouchBarHardwareAvailable {
                    Text("metricsBarSurfaces", bundle: .module)
                } else {
                    Text("metricsBar", bundle: .module)
                }
            } footer: {
                if store.isTouchBarHardwareAvailable {
                    Text("touchBarVisibilityNote", bundle: .module)
                }
            }

            if store.showsMetricsBar || store.isTouchBarMetricsColumnVisible {
                metricTable
            }

            if store.isTouchBarMetricsColumnVisible {
                TouchBarBehaviorSectionView(store: store)
            }

            CustomMetricsSettingsSectionView(store: store.customMetricsSettings)
        }
        .formStyle(.grouped)
        .task {
            await store.send(.viewAppeared(String(describing: Self.self)))
        }
        .onDisappear {
            Task {
                await store.send(.viewDisappeared)
            }
        }
    }

    /// One row per metric with a switch per surface, so both lists share the
    /// same vertical space instead of repeating every metric twice.
    private var metricTable: some View {
        Section {
            HStack(spacing: 0) {
                Text("metric", bundle: .module)
                Spacer(minLength: 8)
                if store.showsMetricsBar {
                    Text("metricsBar", bundle: .module)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: toggleColumnWidth)
                }
                if store.isTouchBarMetricsColumnVisible {
                    Text("touchBar", bundle: .module)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: toggleColumnWidth)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            MetricSurfaceRow(
                title: Text("showCPUUsage", bundle: .module),
                showsOnMenuBar: store.showsMetricsBar ? store.metricsBarConfiguration.showsCPU : nil,
                menuBarAction: { await store.send(.monitorsSystemMetricsToggleSwitched(.cpu, $0)) },
                showsOnTouchBar: store.isTouchBarMetricsColumnVisible ? store.touchBarConfiguration.shows(.cpu) : nil,
                touchBarAction: { await store.send(.touchBarMetricToggleSwitched(.cpu, $0)) }
            )
            MetricSurfaceRow(
                title: Text("showMemoryUsage", bundle: .module),
                showsOnMenuBar: store.showsMetricsBar ? store.metricsBarConfiguration.showsMemory : nil,
                menuBarAction: { await store.send(.monitorsSystemMetricsToggleSwitched(.memory, $0)) },
                showsOnTouchBar: store.isTouchBarMetricsColumnVisible ? store.touchBarConfiguration.shows(.memory) : nil,
                touchBarAction: { await store.send(.touchBarMetricToggleSwitched(.memory, $0)) }
            )
            MetricSurfaceRow(
                title: Text("showStorageCapacity", bundle: .module),
                showsOnMenuBar: store.showsMetricsBar ? store.metricsBarConfiguration.showsStorage : nil,
                menuBarAction: { await store.send(.monitorsSystemMetricsToggleSwitched(.storage, $0)) },
                showsOnTouchBar: store.isTouchBarMetricsColumnVisible ? store.touchBarConfiguration.shows(.storage) : nil,
                touchBarAction: { await store.send(.touchBarMetricToggleSwitched(.storage, $0)) }
            )
            MetricSurfaceRow(
                title: Text("showBatteryStatus", bundle: .module),
                showsOnMenuBar: store.showsMetricsBar ? store.metricsBarConfiguration.showsBattery : nil,
                menuBarAction: { await store.send(.monitorsSystemMetricsToggleSwitched(.battery, $0)) },
                showsOnTouchBar: store.isTouchBarMetricsColumnVisible ? store.touchBarConfiguration.shows(.battery) : nil,
                touchBarAction: { await store.send(.touchBarMetricToggleSwitched(.battery, $0)) }
            )
            MetricSurfaceRow(
                title: Text("showNetworkConnectivity", bundle: .module),
                showsOnMenuBar: store.showsMetricsBar ? store.metricsBarConfiguration.showsNetwork : nil,
                menuBarAction: { await store.send(.monitorsSystemMetricsToggleSwitched(.network, $0)) },
                showsOnTouchBar: store.isTouchBarMetricsColumnVisible ? store.touchBarConfiguration.shows(.network) : nil,
                touchBarAction: { await store.send(.touchBarMetricToggleSwitched(.network, $0)) }
            )
            MetricSurfaceRow(
                title: Text("showFanSpeed", bundle: .module),
                showsOnMenuBar: store.showsMetricsBar ? store.metricsBarConfiguration.showsFan : nil,
                menuBarAction: { await store.send(.monitorsFanToggleSwitched($0)) },
                showsOnTouchBar: store.isTouchBarMetricsColumnVisible ? store.touchBarConfiguration.shows(.fan) : nil,
                touchBarAction: { await store.send(.touchBarMetricToggleSwitched(.fan, $0)) }
            )
            if store.metricsBarConfiguration.showsFan {
                Text("fanZeroSpeedNote", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            MetricSurfaceRow(
                title: Text("showKeyboardBattery", bundle: .module),
                showsOnMenuBar: store.showsMetricsBar ? store.metricsBarConfiguration.showsKeyboardBattery : nil,
                menuBarAction: { await store.send(.monitorsKeyboardBatteryToggleSwitched($0)) },
                showsOnTouchBar: store.isTouchBarMetricsColumnVisible ? store.touchBarConfiguration.shows(.keyboardBattery) : nil,
                touchBarAction: { await store.send(.touchBarMetricToggleSwitched(.keyboardBattery, $0)) }
            )
            if store.keyboardBatteryConfiguration.isEnabled {
                Text("keyboardBatteryPermissionNote", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            MetricSurfaceRow(
                title: Text("showAITokenUsage", bundle: .module),
                showsOnMenuBar: store.showsMetricsBar ? store.metricsBarConfiguration.showsAITokenUsage : nil,
                menuBarAction: { await store.send(.monitorsAITokenUsageToggleSwitched($0)) },
                showsOnTouchBar: store.isTouchBarMetricsColumnVisible ? store.touchBarConfiguration.shows(.aiTokenUsage) : nil,
                touchBarAction: { await store.send(.touchBarMetricToggleSwitched(.aiTokenUsage, $0)) }
            )
            if store.aiTokenUsageConfiguration.isEnabled {
                Text("aiTokenUsagePrivacyNote", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(store.customMetricsSources) { source in
                MetricSurfaceRow(
                    title: Text("show\(source.displayName)Metrics", bundle: .module),
                    showsOnMenuBar: store.showsMetricsBar ? store.metricsBarConfiguration.showsCustomMetrics(of: source.id) : nil,
                    menuBarAction: { await store.send(.monitorsCustomMetricsToggleSwitched(source.id, $0)) },
                    showsOnTouchBar: store.isTouchBarMetricsColumnVisible ? store.touchBarConfiguration.showsCustomMetrics(of: source.id) : nil,
                    touchBarAction: { await store.send(.touchBarCustomMetricsToggleSwitched(source.id, $0)) }
                )
            }
        } header: {
            Text("systemMetrics", bundle: .module)
        }
    }
}

/// One metric row with up to two switches, one per surface. A `nil` surface
/// hides that column, which is how the table keeps its width when it is off.
private struct MetricSurfaceRow: View {
    let title: Text
    let showsOnMenuBar: Bool?
    let menuBarAction: (Bool) async -> Void
    let showsOnTouchBar: Bool?
    let touchBarAction: (Bool) async -> Void

    var body: some View {
        HStack(spacing: 0) {
            title
                .frame(maxWidth: .infinity, alignment: .leading)
            if let showsOnMenuBar {
                Toggle(isOn: Binding<Bool>(
                    get: { showsOnMenuBar },
                    asyncSet: { await menuBarAction($0) }
                )) {
                    Text(verbatim: "")
                }
                .labelsHidden()
                .frame(width: toggleColumnWidth)
            }
            if let showsOnTouchBar {
                Toggle(isOn: Binding<Bool>(
                    get: { showsOnTouchBar },
                    asyncSet: { await touchBarAction($0) }
                )) {
                    Text(verbatim: "")
                }
                .labelsHidden()
                .frame(width: toggleColumnWidth)
            }
        }
    }
}

/// Touch Bar behaviour: display mode and the exclusion list, kept out of the
/// metric table so the table stays short.
private struct TouchBarBehaviorSectionView: View {
    @StateObject var store: MetricsSettings

    var body: some View {
        Section {
            Picker(selection: Binding<TouchBarDisplayMode>(
                get: { store.touchBarConfiguration.mode },
                asyncSet: { await store.send(.touchBarDisplayModeSelected($0)) }
            )) {
                Text("touchBarModeAnchorOnly", bundle: .module).tag(TouchBarDisplayMode.anchorOnly)
                Text("touchBarModeAlwaysExpanded", bundle: .module).tag(TouchBarDisplayMode.alwaysExpanded)
                Text("touchBarModeSmart", bundle: .module).tag(TouchBarDisplayMode.smart)
            } label: {
                Text("touchBarDisplayMode", bundle: .module)
            }
            .pickerStyle(.radioGroup)
            if store.touchBarConfiguration.mode == .smart {
                Text("touchBarSmartModeNote", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if store.touchBarConfiguration.excludedBundleIdentifiers.isEmpty {
                    Text("touchBarNoExcludedApps", bundle: .module)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(store.touchBarExclusionRows, id: \.bundleIdentifier) { row in
                    HStack(spacing: 6) {
                        if let icon = row.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: row.name ?? row.bundleIdentifier)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Text(verbatim: row.bundleIdentifier)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button {
                            Task { await store.send(.touchBarExcludedAppRemoved(row.bundleIdentifier)) }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .labelStyle(.iconOnly)
                    }
                }
                HStack {
                    Button {
                        Task { await store.send(.touchBarExcludeCurrentAppButtonTapped) }
                    } label: {
                        Label {
                            Text("touchBarExcludeCurrentApp", bundle: .module)
                        } icon: {
                            Image(systemName: "plus.circle")
                        }
                    }
                    Button {
                        Task { await store.send(.touchBarAppImporterPresented(true)) }
                    } label: {
                        Label {
                            Text("touchBarAddApps", bundle: .module)
                        } icon: {
                            Image(systemName: "plus.app")
                        }
                    }
                    .fileImporter(
                        isPresented: Binding<Bool>(
                            get: { store.showingTouchBarAppImporter },
                            asyncSet: { await store.send(.touchBarAppImporterPresented($0)) }
                        ),
                        allowedContentTypes: [.application],
                        allowsMultipleSelection: true
                    ) { result in
                        if case .success(let urls) = result {
                            Task { await store.send(.touchBarAppsImported(urls)) }
                        }
                    }
                }
            }
        } header: {
            Text("touchBar", bundle: .module)
        }
    }
}

extension MetricsSettings: ObservableObject {}
