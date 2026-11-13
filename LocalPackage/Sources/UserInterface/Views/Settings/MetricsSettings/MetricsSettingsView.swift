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

struct MetricsSettingsView: View {
    @StateObject var store: MetricsSettings

    private enum SurfaceTab: String, CaseIterable, Identifiable {
        case systemMetrics
        case touchBar
        case stocks

        var id: String { rawValue }
    }

    @State private var surfaceTab: SurfaceTab = .systemMetrics

    var body: some View {
        Form {
            if store.isTouchBarHardwareAvailable {
                Picker(selection: $surfaceTab) {
                    Text("systemMetricsTab", bundle: .module).tag(SurfaceTab.systemMetrics)
                    Text("touchBarTab", bundle: .module).tag(SurfaceTab.touchBar)
                    Text("stockTab", bundle: .module).tag(SurfaceTab.stocks)
                } label: {
                    Text("metricsBarSurfaces", bundle: .module)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            switch surfaceTab {
            case .systemMetrics:
                SystemMetricsTabView(store: store)
            case .touchBar:
                TouchBarTabView(store: store)
            case .stocks:
                StockSectionView(store: store)
            }
        }
        .formStyle(.grouped)
        // Both tabs share this width. Without it the window resizes to each
        // tab's content and visibly widens when the Touch Bar tab is selected.
        .frame(width: 536)
        .task {
            await store.send(.viewAppeared(String(describing: Self.self)))
        }
        .onDisappear {
            Task {
                await store.send(.viewDisappeared)
            }
        }
    }
}

/// Menu bar metrics bar: master switch plus its own metric switches. Turning a
/// metric on here also enables its data collection.
private struct SystemMetricsTabView: View {
    @StateObject var store: MetricsSettings

    var body: some View {
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
            if store.showsMetricsBar {
                Toggle(isOn: Binding<Bool>(
                    get: { store.metricsBarConfiguration.showsCPU },
                    asyncSet: { await store.send(.monitorsSystemMetricsToggleSwitched(.cpu, $0)) }
                )) {
                    Text("showCPUUsage", bundle: .module)
                }
                Toggle(isOn: Binding<Bool>(
                    get: { store.metricsBarConfiguration.showsMemory },
                    asyncSet: { await store.send(.monitorsSystemMetricsToggleSwitched(.memory, $0)) }
                )) {
                    Text("showMemoryUsage", bundle: .module)
                }
                Toggle(isOn: Binding<Bool>(
                    get: { store.metricsBarConfiguration.showsStorage },
                    asyncSet: { await store.send(.monitorsSystemMetricsToggleSwitched(.storage, $0)) }
                )) {
                    Text("showStorageCapacity", bundle: .module)
                }
                Toggle(isOn: Binding<Bool>(
                    get: { store.metricsBarConfiguration.showsBattery },
                    asyncSet: { await store.send(.monitorsSystemMetricsToggleSwitched(.battery, $0)) }
                )) {
                    Text("showBatteryStatus", bundle: .module)
                }
                Toggle(isOn: Binding<Bool>(
                    get: { store.metricsBarConfiguration.showsNetwork },
                    asyncSet: { await store.send(.monitorsSystemMetricsToggleSwitched(.network, $0)) }
                )) {
                    Text("showNetworkConnectivity", bundle: .module)
                }
                Toggle(isOn: Binding<Bool>(
                    get: { store.metricsBarConfiguration.showsFan },
                    asyncSet: { await store.send(.monitorsFanToggleSwitched($0)) }
                )) {
                    Text("showFanSpeed", bundle: .module)
                }
                if store.metricsBarConfiguration.showsFan {
                    Text("fanZeroSpeedNote", bundle: .module)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle(isOn: Binding<Bool>(
                    get: { store.metricsBarConfiguration.showsKeyboardBattery },
                    asyncSet: { await store.send(.monitorsKeyboardBatteryToggleSwitched($0)) }
                )) {
                    Text("showKeyboardBattery", bundle: .module)
                }
                if store.keyboardBatteryConfiguration.isEnabled {
                    Text("keyboardBatteryPermissionNote", bundle: .module)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle(isOn: Binding<Bool>(
                    get: { store.metricsBarConfiguration.showsAITokenUsage },
                    asyncSet: { await store.send(.monitorsAITokenUsageToggleSwitched($0)) }
                )) {
                    Text("showAITokenUsage", bundle: .module)
                }
                if store.aiTokenUsageConfiguration.isEnabled {
                    Text("aiTokenUsagePrivacyNote", bundle: .module)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(store.customMetricsSources) { source in
                    Toggle(isOn: Binding<Bool>(
                        get: { store.metricsBarConfiguration.showsCustomMetrics(of: source.id) },
                        asyncSet: { await store.send(.monitorsCustomMetricsToggleSwitched(source.id, $0)) }
                    )) {
                        Text("show\(source.displayName)Metrics", bundle: .module)
                    }
                }
            }
        } header: {
            Text("metricsBar", bundle: .module)
        }

        CustomMetricsSettingsSectionView(store: store.customMetricsSettings)
    }
}

/// Touch Bar: master switch, its own metric switches, the stock watchlist and
/// the bar behaviour (display mode, priority, exclusions).
private struct TouchBarTabView: View {
    @StateObject var store: MetricsSettings

    var body: some View {
        Section {
            Toggle(isOn: Binding<Bool>(
                get: { store.showsMetricsBarOnTouchBar },
                asyncSet: { await store.send(.showsMetricsBarOnTouchBarToggleSwitched($0)) }
            )) {
                Text("showMetricsBarOnTouchBar", bundle: .module)
            }
            if store.showsMetricsBarOnTouchBar {
                TouchBarMetricToggleRow(store: store, metric: .cpu, title: "showCPUUsage")
                TouchBarMetricToggleRow(store: store, metric: .memory, title: "showMemoryUsage")
                TouchBarMetricToggleRow(store: store, metric: .storage, title: "showStorageCapacity")
                TouchBarMetricToggleRow(store: store, metric: .battery, title: "showBatteryStatus")
                TouchBarMetricToggleRow(store: store, metric: .network, title: "showNetworkConnectivity")
                TouchBarMetricToggleRow(store: store, metric: .fan, title: "showFanSpeed")
                TouchBarMetricToggleRow(store: store, metric: .keyboardBattery, title: "showKeyboardBattery")
                TouchBarMetricToggleRow(store: store, metric: .aiTokenUsage, title: "showAITokenUsage")
                ForEach(store.customMetricsSources) { source in
                    HStack(spacing: 8) {
                        Toggle(isOn: Binding<Bool>(
                            get: { store.touchBarConfiguration.showsCustomMetrics(of: source.id) },
                            asyncSet: { await store.send(.touchBarCustomMetricsToggleSwitched(source.id, $0)) }
                        )) {
                            Text("show\(source.displayName)Metrics", bundle: .module)
                        }
                        StackAssignmentMenu(store: store, member: .customMetric(source.id))
                            .disabled(!store.touchBarConfiguration.showsCustomMetrics(of: source.id))
                    }
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("touchBarVisibilityNote", bundle: .module)
                Text("touchBarStackNote", bundle: .module)
            }
            .fixedSize(horizontal: false, vertical: true)
        }

        if store.showsMetricsBarOnTouchBar {
            TouchBarBehaviorSectionView(store: store)
        }
    }
}

/// One Touch Bar metric toggle with its stack menu. The menu is disabled while
/// the metric is hidden: an invisible item has nothing to stack.
private struct TouchBarMetricToggleRow: View {
    @StateObject var store: MetricsSettings
    let metric: TouchBarMetric
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding<Bool>(
                get: { store.touchBarConfiguration.shows(metric) },
                asyncSet: { await store.send(.touchBarMetricToggleSwitched(metric, $0)) }
            )) {
                Text(title, bundle: .module)
            }
            StackAssignmentMenu(store: store, member: .metric(metric))
                .disabled(!store.touchBarConfiguration.shows(metric))
        }
    }
}

/// Assigns an item to a stack. Only stacks of the item's own group are
/// offered (metrics and stocks never mix), plus a "new stack" entry until the
/// cap is reached.
private struct StackAssignmentMenu: View {
    @StateObject var store: MetricsSettings
    let member: TouchBarMember

    private enum Choice: Hashable {
        case independent
        case stack(UUID)
        case new
    }

    private static func stackLabel(_ number: Int) -> String {
        String(format: String(localized: "stackNumber", bundle: .module), number)
    }

    var body: some View {
        Picker(selection: Binding<Choice>(
            get: {
                store.touchBarConfiguration.stack(containing: member).map { .stack($0.id) } ?? .independent
            },
            asyncSet: { choice in
                switch choice {
                case .independent:
                    await store.send(.touchBarMemberStackAssignmentSelected(member, .independent))
                case let .stack(id):
                    await store.send(.touchBarMemberStackAssignmentSelected(member, .stack(id)))
                case .new:
                    await store.send(.touchBarMemberStackAssignmentSelected(member, .newStack))
                }
            }
        )) {
            Text("stackIndependent", bundle: .module).tag(Choice.independent)
            ForEach(store.compatibleStacks(for: member)) { stack in
                Text(verbatim: Self.stackLabel(store.stackNumber(of: stack) ?? 0))
                    .tag(Choice.stack(stack.id))
            }
            if store.canCreateStack {
                Text("stackNew", bundle: .module).tag(Choice.new)
            }
        } label: {
            Text("touchBarStack", bundle: .module)
        }
        .labelsHidden()
        .pickerStyle(.menu)
        // Wide enough for the longest localized option ("Eigenständig") plus
        // the chevron, so the menu title never truncates.
        .frame(width: 128)
    }
}

/// Touch Bar behaviour: display mode, display priority and the exclusion list.
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
            Picker(selection: Binding<Bool>(
                get: { store.touchBarConfiguration.prioritizeStocks },
                asyncSet: { await store.send(.touchBarStockPrioritySwitched($0)) }
            )) {
                Text("touchBarPriorityMetrics", bundle: .module).tag(false)
                Text("touchBarPriorityStocks", bundle: .module).tag(true)
            } label: {
                Text("touchBarPriority", bundle: .module)
            }
            .pickerStyle(.radioGroup)
            Toggle(isOn: Binding<Bool>(
                get: { store.touchBarConfiguration.showsRunner },
                asyncSet: { await store.send(.touchBarShowsRunnerToggleSwitched($0)) }
            )) {
                Text("touchBarShowsRunner", bundle: .module)
            }
            if store.touchBarConfiguration.mode == .smart {
                Text("touchBarSmartModeNote", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if store.touchBarConfiguration.excludedBundleIdentifiers.isEmpty {
                    Text("touchBarNoExcludedApps", bundle: .module)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
            Text("touchBarBehavior", bundle: .module)
        }
    }
}

/// The Touch Bar watchlist: rows with abbreviation and symbol, one sheet editor
/// shared for adding. Stocks appear on the Touch Bar only.
private struct StockSectionView: View {
    @StateObject var store: MetricsSettings

    /// "5 s" / "5 秒" comes from the system formatter, so the four options need
    /// no locale-specific strings.
    private static func intervalLabel(_ seconds: Int) -> String {
        Measurement(value: Double(seconds), unit: UnitDuration.seconds)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided))
    }

    var body: some View {
        Section {
            Picker(selection: Binding<Int>(
                get: { store.stockConfiguration.refreshInterval },
                asyncSet: { await store.send(.stockRefreshIntervalSelected($0)) }
            )) {
                ForEach(StockConfiguration.refreshIntervalOptions, id: \.self) { seconds in
                    Text(verbatim: Self.intervalLabel(seconds)).tag(seconds)
                }
            } label: {
                Text("stockRefreshInterval", bundle: .module)
            }
            .pickerStyle(.menu)
            ForEach(store.stocks) { stock in
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: stock.abbreviation)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Text(verbatim: stock.symbol)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    StackAssignmentMenu(store: store, member: .stock(stock.id))
                    Button {
                        Task { await store.send(.removeStockButtonTapped(stock.id)) }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
                }
            }
            Button {
                Task { await store.send(.addStockButtonTapped) }
            } label: {
                Label {
                    Text("stockAdd", bundle: .module)
                } icon: {
                    Image(systemName: "plus.circle")
                }
            }
            Text("stockSymbolHint", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("touchBarStackNote", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(item: $store.stockEditor) { editor in
            StockEditorView(store: editor)
        }
    }
}

/// Sheet editor for one stock: the code is validated with a live quote fetch
/// before it lands in the watchlist.
private struct StockEditorView: View {
    @Bindable var store: StockEditor

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(text: $store.symbol) {
                        Text("stockSymbol", bundle: .module)
                    }
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    TextField(text: $store.abbreviation) {
                        Text("stockAbbreviation", bundle: .module)
                    }
                    .textFieldStyle(.roundedBorder)
                } footer: {
                    Text("stockSymbolHint", bundle: .module)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text("stockEditorTitle", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        Task { await store.send(.cancelButtonTapped) }
                    } label: {
                        Text("cancel", bundle: .module)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await store.send(.addButtonTapped) }
                    } label: {
                        if store.isFetching {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("add", bundle: .module)
                        }
                    }
                    .disabled(!store.canAdd || store.isFetching)
                }
            }
            .alert(isPresented: $store.showingAlert, error: store.error, actions: { _ in }, message: { _ in })
        }
        .frame(width: 380)
        .fixedSize()
    }
}

extension MetricsSettings: ObservableObject {}
