/*
 TouchBarMetricsContainerView.swift
 UserInterface

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

import AppKit
import DataSource
import Model
import Observation

/// Hosts the Touch Bar metrics bar built with plain AppKit views.
///
/// SwiftUI content does not render reliably inside a Touch Bar item
/// (`Image(size:)` canvases come out transparent and hosted layouts drift out
/// of their bounds), so this view assembles NSStackView/NSTextField cells.
/// The prioritized group hugs its content at the leading edge and the other
/// group is laid out in a fixed-width scroll view. That scroll view only clips
/// overflow: the Touch Bar never delivers swipe events to the app, so nothing
/// can actually scroll there — the cell sizes are chosen so all watchlist
/// entries and metrics fit instead. Items grouped into a stack share one fixed
/// slot and rotate every three seconds with a bottom-to-top roll. Tapping a
/// stock swaps the whole bar for its detail panel.
public final class TouchBarMetricsContainerView: NSView {
    private let store: MetricsBar

    /// The prioritized group's stack. It is also the host of the detail panel,
    /// which always spans the whole bar.
    private let leadingStack = NSStackView()
    private let leadingStocksStack = NSStackView()
    private let metricsScrollStack = NSStackView()
    private let stocksScrollStack = NSStackView()
    private let scrollView = NSScrollView()
    private let separatorView = NSView()
    /// The menu-bar runner, shown at the leading edge of the prioritized
    /// group when the configuration enables it. The view persists across
    /// rebuilds; rebuilds only move it in or out of the pinned stack.
    private let runnerView = TouchBarRunnerView()

    private var expandedStockID: UUID?
    private var lastMetricStructure: [String] = []
    private var lastStockStructure: [String] = []
    private var lastExpandedID: UUID?
    private var lastPrioritizeStocks: Bool?
    private var lastShowsStocks = false
    private var lastShowsRunner: Bool?
    private var lastHasRunner = false
    private var lastRunnerVersion = 0
    private var lastRunnerSpeed: Float = 1
    private var lifecycleTask: Task<Void, Never>?
    private var lifecycleGeneration = 0
    private var rotationTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isSessionActive = true
    private var isSystemSleeping = false
    private var lastMetricIconSymbols: [String: String] = [:]
    private var rebuildPending = false
    private var layoutConstraints: [NSLayoutConstraint] = []
    /// Rotation phase per stack slot, preserved across structural rebuilds.
    private var rotationPhases: [String: Int] = [:]
    private var stackViews: [(id: String, view: TouchBarStackView)] = []

    /// The system-modal bar's viewport is narrower than the DFR display: on a
    /// 1085pt Touch Bar the host gives the bar 621pt and clips anything wider
    /// (measured from `NSTouchBarView`'s frame), so the item must request
    /// exactly that or its trailing content is cut off.
    static let barWidth: CGFloat = 621
    static let height: CGFloat = 28
    private static let documentHeight: CGFloat = height - 4
    private static let horizontalInset: CGFloat = 12
    private static let separatorGap: CGFloat = 10
    /// Stacked indicators advance one member every three seconds.
    private static let rotationInterval: TimeInterval = 3

    public init(_ appDependencies: AppDependencies) {
        store = MetricsBar(appDependencies, touchBarRunnerImageProvider: { resourceName in
            NSImage(resource: .init(name: resourceName, bundle: .module))
        })
        super.init(frame: NSRect(x: 0, y: 0, width: Self.barWidth, height: Self.height))
        wantsLayer = true
        layer?.backgroundColor = TouchBarOLEDTheme.background.cgColor
        layer?.cornerRadius = 5

        for stack in [leadingStack, leadingStocksStack] {
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 10
            stack.translatesAutoresizingMaskIntoConstraints = false
        }
        leadingStocksStack.spacing = 8

        // Document views are sized by hand after every rebuild so the scroll
        // view has a content width to scroll within.
        for stack in [metricsScrollStack, stocksScrollStack] {
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 10
            stack.translatesAutoresizingMaskIntoConstraints = true
            stack.frame = NSRect(x: 0, y: 0, width: Self.barWidth, height: Self.documentHeight)
        }
        stocksScrollStack.spacing = 8

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        separatorView.wantsLayer = true
        separatorView.layer?.backgroundColor = TouchBarOLEDTheme.separator.cgColor
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        // A separator without a size renders as nothing.
        NSLayoutConstraint.activate([
            separatorView.widthAnchor.constraint(equalToConstant: 1),
            separatorView.heightAnchor.constraint(equalToConstant: 20),
        ])

        // Touch Bar content is dimmed while the macOS login session is
        // inactive (for example, the screen is locked) and rotation pauses
        // during sleep. These are system lifecycle signals, not input
        // monitoring; no accessibility or event-monitoring permission needed.
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleSessionInactive() }
        })
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleSessionActive() }
        })
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleSystemSleep() }
        })
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleSystemWake() }
        })
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: Self.barWidth, height: Self.height)
    }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        stopRotationTimer()
        lifecycleTask?.cancel()
        lifecycleGeneration += 1
        let generation = lifecycleGeneration

        guard superview != nil else {
            lifecycleTask = Task { @MainActor [weak self] in
                guard let self, self.lifecycleGeneration == generation else { return }
                await self.store.send(.viewDisappeared)
            }
            return
        }

        lifecycleTask = Task { @MainActor [weak self] in
            guard let self, self.lifecycleGeneration == generation else { return }
            await self.store.send(.viewAppeared(String(describing: TouchBarMetricsContainerView.self)))
            guard self.lifecycleGeneration == generation else { return }
            self.scheduleRebuildIfNeeded()
            self.updateVisibleValues()
            self.updateRunnerIfNeeded()
            self.observeStoreChanges()
            self.startRotationTimer()
        }
    }

    private func startRotationTimer() {
        guard superview != nil,
              isSessionActive,
              !isSystemSleeping,
              rotationTimer == nil else { return }
        // `.common` keeps the rotation ticking while a gesture is tracking.
        let timer = Timer(timeInterval: Self.rotationInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.rotateStacks() }
        }
        RunLoop.main.add(timer, forMode: .common)
        rotationTimer = timer
    }

    private func stopRotationTimer() {
        rotationTimer?.invalidate()
        rotationTimer = nil
    }

    private func handleSessionInactive() {
        isSessionActive = false
        alphaValue = 0.55
        stopRotationTimer()
    }

    private func handleSessionActive() {
        isSessionActive = true
        if !isSystemSleeping {
            alphaValue = 1
            startRotationTimer()
        }
    }

    private func handleSystemSleep() {
        isSystemSleeping = true
        stopRotationTimer()
    }

    private func handleSystemWake() {
        isSystemSleeping = false
        alphaValue = isSessionActive ? 1 : 0.55
        startRotationTimer()
    }

    /// Observation tracking is one-shot; re-arm after every store change.
    /// This replaces the old 0.5-second polling loop.
    private func observeStoreChanges() {
        guard superview != nil else { return }
        withObservationTracking {
            _ = store.touchBarMetricSlots
            _ = store.touchBarStockSlots
            _ = store.touchBarConfiguration
            _ = store.stockConfiguration
            _ = store.touchBarRunnerVersion
            _ = store.touchBarRunnerSpeed
            _ = store.touchBarRunnerFrames
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.superview != nil else { return }
                self.scheduleRebuildIfNeeded()
                self.updateVisibleValues()
                self.updateRunnerIfNeeded()
                self.observeStoreChanges()
            }
        }
    }

    /// Updates labels in place when values change; only structural changes
    /// rebuild the AppKit view hierarchy.
    private func updateVisibleValues() {
        var values: [String: (String, NSColor)] = [:]
        var icons: [String: (String, NSColor)] = [:]
        for indicator in store.touchBarIndicators {
            let prefix = "metric:\(indicator.member.key):"
            values[prefix + "primary"] = (indicator.primaryText, TouchBarOLEDTheme.dynamicValue)
            icons[prefix + "icon"] = (indicator.systemIcon, TouchBarOLEDTheme.staticIcon)
            if let secondary = indicator.secondaryText {
                values[prefix + "secondary"] = (secondary, TouchBarOLEDTheme.dynamicValue)
            }
        }
        for indicator in store.stockIndicators {
            let prefix = "stock:\(indicator.id.uuidString):"
            let tint = TouchBarOLEDTheme.color(for: indicator.direction)
            values[prefix + "name"] = (indicator.abbreviation, tint)
            values[prefix + "change"] = (String(format: "%+.2f%%", indicator.changePercent), tint)
            values[prefix + "detail-name"] = (indicator.name, tint)
            values[prefix + "detail-line"] = (detailString(quote: indicator.quote), tint)
            values[prefix + "detail-change"] = (String(format: "%+.2f%%", indicator.changePercent), tint)
        }

        func update(_ view: NSView) {
            if let field = view as? NSTextField,
               let key = field.identifier?.rawValue,
               let value = values[key] {
                if field.stringValue != value.0 { field.stringValue = value.0 }
                field.textColor = value.1
            } else if let imageView = view as? NSImageView,
                      let key = imageView.identifier?.rawValue,
                      let value = icons[key] {
                if lastMetricIconSymbols[key] != value.0 {
                    imageView.image = NSImage(
                        systemSymbolName: value.0,
                        accessibilityDescription: value.0
                    )?.withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
                    lastMetricIconSymbols[key] = value.0
                }
                imageView.contentTintColor = value.1
            }
            for child in view.subviews { update(child) }
        }
        lastMetricIconSymbols = lastMetricIconSymbols.filter { icons[$0.key] != nil }
        update(self)
        if let documentStack = scrollView.documentView as? NSStackView {
            sizeDocumentView(documentStack)
        }
        needsLayout = true
    }

    /// Compares the store's slot snapshots and, when they drifted, asks for a
    /// deferred rebuild. The rebuild never runs inside a layout pass, where
    /// mutating the hierarchy crashes AppKit.
    private func scheduleRebuildIfNeeded() {
        let metricSlots = store.touchBarMetricSlots
        let stockSlots = store.touchBarStockSlots
        let metricStructure = metricSlots.map { slot in
            "\(slot.id):\(slot.indicators.map { $0.member.key }.joined(separator: ","))"
        }
        let stockStructure = stockSlots.map { slot in
            "\(slot.id):\(slot.indicators.map { $0.id.uuidString }.joined(separator: ","))"
        }
        let prioritizeStocks = store.touchBarConfiguration.prioritizeStocks
        let showsStocks = store.stockConfiguration.stocks.isEmpty == false
        let showsRunner = store.touchBarConfiguration.showsRunner
        let hasRunner = store.touchBarRunnerVersion > 0
        guard metricStructure != lastMetricStructure
            || stockStructure != lastStockStructure
            || expandedStockID != lastExpandedID
            || prioritizeStocks != lastPrioritizeStocks
            || showsStocks != lastShowsStocks
            || showsRunner != lastShowsRunner
            || hasRunner != lastHasRunner else {
            return
        }
        lastMetricStructure = metricStructure
        lastStockStructure = stockStructure
        lastExpandedID = expandedStockID
        lastPrioritizeStocks = prioritizeStocks
        lastShowsStocks = showsStocks
        lastShowsRunner = showsRunner
        lastHasRunner = hasRunner
        updateVisibleValues()
        guard !rebuildPending else { return }
        rebuildPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            rebuildPending = false
            rebuild(
                metricSlots: store.touchBarMetricSlots,
                stockSlots: store.touchBarStockSlots,
                prioritizeStocks: store.touchBarConfiguration.prioritizeStocks,
                showsStocks: store.stockConfiguration.stocks.isEmpty == false
            )
        }
    }

    /// Feeds the persistent runner view without a layout rebuild: frame and
    /// speed changes only touch the animation layer.
    private func updateRunnerIfNeeded() {
        let version = store.touchBarRunnerVersion
        if version != lastRunnerVersion {
            lastRunnerVersion = version
            runnerView.set(frames: store.touchBarRunnerFrames, isTemplate: store.touchBarRunnerIsTemplate)
        }
        let speed = store.touchBarRunnerSpeed
        if speed != lastRunnerSpeed {
            lastRunnerSpeed = speed
            runnerView.setSpeed(speed)
        }
    }

    /// Relays out the bar: the prioritized group hugs its content at the
    /// leading edge, the other group fills a scroll view in the remaining
    /// width. Only the views a state needs are in the hierarchy: an unused
    /// separator would otherwise keep drawing its old frame.
    private func rebuild(
        metricSlots: [TouchBarMetricSlot],
        stockSlots: [TouchBarStockSlot],
        prioritizeStocks: Bool,
        showsStocks: Bool
    ) {
        stackViews.removeAll()
        let stockIndicators = stockSlots.flatMap(\.indicators)
        NSLayoutConstraint.deactivate(layoutConstraints)
        layoutConstraints.removeAll()
        for stack in [leadingStack, leadingStocksStack, metricsScrollStack, stocksScrollStack] {
            stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        }
        leadingStack.removeFromSuperview()
        leadingStocksStack.removeFromSuperview()
        scrollView.removeFromSuperview()
        separatorView.removeFromSuperview()
        metricsScrollStack.removeFromSuperview()
        stocksScrollStack.removeFromSuperview()

        if let expanded = stockIndicators.first(where: { $0.id == expandedStockID }) {
            // While a stock is expanded the whole bar belongs to its detail.
            runnerView.removeFromSuperview()
            leadingStack.addArrangedSubview(makeDetailPanel(for: expanded))
            addSubview(leadingStack)
            layoutConstraints = [
                leadingStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalInset),
                leadingStack.centerYAnchor.constraint(equalTo: centerYAnchor),
                leadingStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalInset),
            ]
            NSLayoutConstraint.activate(layoutConstraints)
            return
        }

        // Build only the active presentation of each group. The previous
        // implementation built pinned and scrolling copies simultaneously,
        // doubling the NSView/NSImageView/NSTextField count.
        if prioritizeStocks && showsStocks {
            populateStocks(into: leadingStocksStack, slots: stockSlots)
            populateMetrics(into: metricsScrollStack, slots: metricSlots)
        } else {
            populateMetrics(into: leadingStack, slots: metricSlots)
            populateStocks(into: stocksScrollStack, slots: stockSlots)
        }
        // Forget phases for stacks that no longer exist, keeping the map
        // bounded and making a re-created stack start from its first member.
        let liveStackIDs = Set(store.touchBarConfiguration.stacks.map(\.slotID))
        rotationPhases = rotationPhases.filter { liveStackIDs.contains($0.key) }

        // The runner leads the pinned group; it is one persistent view moved
        // between the two possible pinned stacks.
        let showsRunner = store.touchBarConfiguration.showsRunner && store.touchBarRunnerVersion > 0
        let pinnedStack = prioritizeStocks && showsStocks ? leadingStocksStack : leadingStack
        if showsRunner {
            pinnedStack.insertArrangedSubview(runnerView, at: 0)
        } else {
            runnerView.removeFromSuperview()
        }

        if prioritizeStocks && showsStocks {
            addSubview(leadingStocksStack)
            layoutConstraints = [
                leadingStocksStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalInset),
                leadingStocksStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            ]
            if !metricSlots.isEmpty {
                addSubview(separatorView)
                addSubview(scrollView)
                scrollView.documentView = metricsScrollStack
                sizeDocumentView(metricsScrollStack)
                layoutConstraints.append(contentsOf: [
                    separatorView.leadingAnchor.constraint(equalTo: leadingStocksStack.trailingAnchor, constant: Self.separatorGap),
                    separatorView.centerYAnchor.constraint(equalTo: centerYAnchor),
                    scrollView.leadingAnchor.constraint(equalTo: separatorView.trailingAnchor, constant: Self.separatorGap),
                    scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalInset),
                    scrollView.centerYAnchor.constraint(equalTo: centerYAnchor),
                    scrollView.heightAnchor.constraint(equalToConstant: Self.documentHeight),
                ])
            }
        } else {
            addSubview(leadingStack)
            layoutConstraints = [
                leadingStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalInset),
                leadingStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            ]
            if showsStocks {
                addSubview(separatorView)
                addSubview(scrollView)
                scrollView.documentView = stocksScrollStack
                sizeDocumentView(stocksScrollStack)
                layoutConstraints.append(contentsOf: [
                    separatorView.leadingAnchor.constraint(equalTo: leadingStack.trailingAnchor, constant: Self.separatorGap),
                    separatorView.centerYAnchor.constraint(equalTo: centerYAnchor),
                    scrollView.leadingAnchor.constraint(equalTo: separatorView.trailingAnchor, constant: Self.separatorGap),
                    scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalInset),
                    scrollView.centerYAnchor.constraint(equalTo: centerYAnchor),
                    scrollView.heightAnchor.constraint(equalToConstant: Self.documentHeight),
                ])
            }
        }
        NSLayoutConstraint.activate(layoutConstraints)
    }

    /// The document view's frame drives how much the scroll view can scroll,
    /// so it must be sized from the stack's content width explicitly.
    private func sizeDocumentView(_ stack: NSStackView) {
        stack.layoutSubtreeIfNeeded()
        let fitting = stack.fittingSize
        stack.frame = NSRect(
            x: 0,
            y: 0,
            width: max(fitting.width, 1),
            height: Self.documentHeight
        )
    }

    private func populateMetrics(into stack: NSStackView, slots: [TouchBarMetricSlot]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if slots.isEmpty {
            stack.addArrangedSubview(makeIconCell("moon.zzz", tint: TouchBarOLEDTheme.staticIcon))
            return
        }
        for slot in slots {
            if slot.isStack {
                addStackView(id: slot.id, cells: slot.indicators.map(makeMetricCell(for:)), into: stack)
            } else if let indicator = slot.indicators.first {
                stack.addArrangedSubview(makeMetricCell(for: indicator))
            }
        }
    }

    private func populateStocks(into stack: NSStackView, slots: [TouchBarStockSlot]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for slot in slots {
            if slot.isStack {
                addStackView(id: slot.id, cells: slot.indicators.map { makeStockCell(for: $0) }, into: stack)
            } else if let indicator = slot.indicators.first {
                stack.addArrangedSubview(makeStockCell(for: indicator))
            }
        }
    }

    /// A stack slot is as wide as its widest member, so rotating never shifts
    /// the neighbouring cells. The view resumes from the last recorded phase.
    private func addStackView(id: String, cells: [NSView], into stack: NSStackView) {
        let width = cells.map { fittingWidth(of: $0) }.max() ?? 1
        let view = TouchBarStackView(members: cells, width: width, height: Self.documentHeight)
        view.setActive(index: rotationPhases[id] ?? 0)
        stack.addArrangedSubview(view)
        stackViews.append((id, view))
    }

    private func fittingWidth(of view: NSView) -> CGFloat {
        view.layoutSubtreeIfNeeded()
        return ceil(view.fittingSize.width)
    }

    private func makeMetricCell(for indicator: TouchBarIndicator) -> NSView {
        let cell = NSStackView()
        cell.orientation = .horizontal
        cell.alignment = .centerY
        cell.spacing = 3
        let iconView = makeIconCell(indicator.systemIcon, tint: TouchBarOLEDTheme.staticIcon)
        iconView.identifier = NSUserInterfaceItemIdentifier("metric:\(indicator.member.key):icon")
        cell.addArrangedSubview(iconView)
        if let secondaryText = indicator.secondaryText {
            // Upload and download stack vertically, keeping the footprint
            // of the pair small.
            let column = NSStackView()
            column.orientation = .vertical
            column.alignment = .leading
            column.spacing = 1
            column.addArrangedSubview(makeTextCell(
                indicator.primaryText,
                font: .monospacedDigitSystemFont(ofSize: 8, weight: .regular),
                tint: TouchBarOLEDTheme.dynamicValue,
                identifier: "metric:\(indicator.member.key):primary"
            ))
            column.addArrangedSubview(makeTextCell(
                secondaryText,
                font: .monospacedDigitSystemFont(ofSize: 8, weight: .regular),
                tint: TouchBarOLEDTheme.dynamicValue,
                identifier: "metric:\(indicator.member.key):secondary"
            ))
            cell.addArrangedSubview(column)
        } else {
            cell.addArrangedSubview(makeTextCell(
                indicator.primaryText,
                font: .monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                tint: TouchBarOLEDTheme.dynamicValue,
                identifier: "metric:\(indicator.member.key):primary"
            ))
        }
        return cell
    }

    /// Abbreviation over change percent: two narrow lines make five stocks fit
    /// the width the system-modal bar allows without any scrolling.
    private func makeStockCell(for indicator: StockIndicator) -> NSView {
        let tint = color(for: indicator.direction)
        let cell = NSStackView()
        cell.orientation = .vertical
        cell.alignment = .leading
        cell.spacing = 0
        cell.identifier = NSUserInterfaceItemIdentifier(indicator.id.uuidString)
        cell.addArrangedSubview(makeTextCell(
            indicator.abbreviation,
            font: .systemFont(ofSize: 9, weight: .medium),
            tint: tint,
            identifier: "stock:\(indicator.id.uuidString):name"
        ))
        cell.addArrangedSubview(makeTextCell(
            String(format: "%+.2f%%", indicator.changePercent),
            font: .monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            tint: tint,
            identifier: "stock:\(indicator.id.uuidString):change"
        ))
        let tap = NSClickGestureRecognizer(target: self, action: #selector(stockCellTapped(_:)))
        cell.addGestureRecognizer(tap)
        return cell
    }

    private func makeDetailPanel(for indicator: StockIndicator) -> NSView {
        let quote = indicator.quote
        let panel = NSStackView()
        panel.orientation = .horizontal
        panel.alignment = .centerY
        panel.spacing = 10

        panel.addArrangedSubview(makeIconCell("chart.line.uptrend.xyaxis", tint: color(for: indicator.direction)))
        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.addArrangedSubview(makeTextCell(
            indicator.name,
            font: .systemFont(ofSize: 12, weight: .semibold),
            tint: TouchBarOLEDTheme.color(for: indicator.direction),
            identifier: "stock:\(indicator.id.uuidString):detail-name"
        ))
        textStack.addArrangedSubview(makeTextCell(
            detailString(quote: quote),
            font: .monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            tint: TouchBarOLEDTheme.color(for: indicator.direction),
            identifier: "stock:\(indicator.id.uuidString):detail-line"
        ))
        panel.addArrangedSubview(textStack)
        panel.addArrangedSubview(makeTextCell(
            String(format: "%+.2f%%", indicator.changePercent),
            font: .monospacedDigitSystemFont(ofSize: 14, weight: .semibold),
            tint: TouchBarOLEDTheme.color(for: indicator.direction),
            identifier: "stock:\(indicator.id.uuidString):detail-change"
        ))
        // The panel spans the bar, so an elastic spacer keeps the content
        // hugging the leading edge instead of letting AppKit spread the slack.
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        panel.addArrangedSubview(spacer)

        let tap = NSClickGestureRecognizer(target: self, action: #selector(detailPanelTapped(_:)))
        panel.addGestureRecognizer(tap)
        return panel
    }

    private func makeIconCell(_ systemName: String, tint: NSColor) -> NSImageView {
        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        imageView.contentTintColor = tint
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: 16).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 13).isActive = true
        return imageView
    }

    private func makeTextCell(
        _ text: String,
        font: NSFont,
        tint: NSColor,
        identifier: String? = nil
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = tint
        if let identifier {
            field.identifier = NSUserInterfaceItemIdentifier(identifier)
        }
        field.lineBreakMode = .byClipping
        field.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        field.setContentHuggingPriority(.required, for: .horizontal)
        return field
    }

    private func detailString(quote: StockQuote) -> String {
        let price = quote.price.map { String(format: "%.2f", $0) } ?? "--"
        let open = quote.open.map { String(format: "%.2f", $0) } ?? "--"
        let high = quote.high.map { String(format: "%.2f", $0) } ?? "--"
        let low = quote.low.map { String(format: "%.2f", $0) } ?? "--"
        let change = quote.changeAmount.map { String(format: "%+.2f", $0) } ?? "--"
        return String(
            format: String(localized: "stockDetailLine", bundle: .module),
            price, change, open, high, low
        )
    }

    private func color(for direction: StockDirection) -> NSColor {
        TouchBarOLEDTheme.color(for: direction)
    }

    // MARK: - Rotation

    /// Advances each active stack one member. Inactive presentation copies
    /// are no longer built, so every entry here is a live candidate.
    private func rotateStacks() {
        guard expandedStockID == nil else { return }
        var advanced = Set<String>()
        for entry in stackViews where isInHierarchy(entry.view) {
            guard entry.view.memberCount > 1 else { continue }
            if advanced.contains(entry.id) {
                entry.view.setActive(index: rotationPhases[entry.id] ?? 0)
                continue
            }
            advanced.insert(entry.id)
            let next = ((rotationPhases[entry.id] ?? 0) + 1) % entry.view.memberCount
            rotationPhases[entry.id] = next
            entry.view.advance()
        }
    }

    /// Returns whether a stack belongs to the currently attached hierarchy.
    private func isInHierarchy(_ view: NSView) -> Bool {
        var ancestor = view.superview
        while let current = ancestor {
            if current === self { return true }
            ancestor = current.superview
        }
        return false
    }

    // MARK: - Actions

    @objc private func stockCellTapped(_ sender: NSClickGestureRecognizer) {
        guard let identifier = sender.view?.identifier?.rawValue,
              let stock = store.stockConfiguration.stocks.first(where: { $0.id.uuidString == identifier }) else {
            return
        }
        expandedStockID = stock.id
        scheduleRebuildIfNeeded()
    }

    @objc private func detailPanelTapped(_ sender: NSClickGestureRecognizer) {
        expandedStockID = nil
        scheduleRebuildIfNeeded()
    }
}
