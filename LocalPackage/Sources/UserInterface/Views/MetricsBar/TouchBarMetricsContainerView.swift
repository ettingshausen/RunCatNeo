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
    /// All custom content lives in this clipped container. Moving this view
    /// keeps AppKit hit-testing aligned with the pixels during Pixel Shift.
    private let contentContainerView = NSView()
    private var contentCenterXConstraint: NSLayoutConstraint!
    private var contentCenterYConstraint: NSLayoutConstraint!

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

    /// The bar's own control pages. Like the stock detail, one of them owns the
    /// whole bar while it is open, and rotation is suspended.
    private enum Panel: Equatable {
        case menu
        case runnerPicker
        case brightness
    }

    private var panel: Panel?
    private var runnerPickerPage = 0
    private let panelStack = NSStackView()
    /// Set while the system close box is already hidden, so the deferred
    /// re-hide does not loop.
    private var systemCloseBoxHidden = false

    private var expandedStockID: UUID?
    private var lastMetricStructure: [String] = []
    private var lastStockStructure: [String] = []
    private var lastExpandedID: UUID?
    private var lastPanel: Panel?
    private var lastRunnerPickerPage = 0
    private var lastRunnerListCount = 0
    private var lastPrioritizeStocks: Bool?
    private var lastShowsStocks = false
    private var lastShowsRunner: Bool?
    private var lastHasRunner = false
    private var lastRunnerVersion = 0
    private var lastRunnerSpeed: Float = 1
    private var lifecycleTask: Task<Void, Never>?
    private var lifecycleGeneration = 0
    private var rotationTimer: Timer?
    private var pixelShiftTimer: Timer?
    private var pixelShiftIndex = 0
    private var workspaceObservers: [NSObjectProtocol] = []
    private var defaultsObserver: NSObjectProtocol?
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
    private static let pixelShiftInterval: TimeInterval = 300

    public init(_ appDependencies: AppDependencies) {
        store = MetricsBar(appDependencies, touchBarRunnerImageProvider: { resourceName in
            NSImage(resource: .init(name: resourceName, bundle: .module))
        })
        super.init(frame: NSRect(x: 0, y: 0, width: Self.barWidth, height: Self.height))
        TouchBarOLEDTheme.registerDefaults()
        wantsLayer = true
        layer?.backgroundColor = TouchBarOLEDTheme.background.cgColor
        layer?.cornerRadius = 5
        layer?.masksToBounds = true

        contentContainerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentContainerView)
        contentCenterXConstraint = contentContainerView.centerXAnchor.constraint(
            equalTo: centerXAnchor
        )
        contentCenterYConstraint = contentContainerView.centerYAnchor.constraint(
            equalTo: centerYAnchor
        )
        NSLayoutConstraint.activate([
            contentCenterXConstraint,
            contentCenterYConstraint,
            contentContainerView.widthAnchor.constraint(equalTo: widthAnchor),
            contentContainerView.heightAnchor.constraint(equalTo: heightAnchor),
        ])

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

        panelStack.orientation = .horizontal
        panelStack.alignment = .centerY
        panelStack.spacing = 8
        panelStack.translatesAutoresizingMaskIntoConstraints = false

        // The runner is the bar's control entry point. Its width is 0 until
        // frames arrive, so a minimum keeps it tappable from the first layout.
        runnerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            runnerView.widthAnchor.constraint(greaterThanOrEqualToConstant: 28),
            runnerView.heightAnchor.constraint(equalToConstant: TouchBarRunnerView.hostHeight),
        ])
        let runnerTap = NSClickGestureRecognizer(target: self, action: #selector(runnerTapped(_:)))
        runnerView.addGestureRecognizer(runnerTap)
    }

    /// Register workspace notifications only while the Touch Bar view is
    /// attached. This avoids retaining notification tokens for an inactive
    /// Touch Bar instance.
    private func installWorkspaceObservers() {
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleSessionInactive() }
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleSessionActive() }
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleSystemSleep() }
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleSystemWake() }
        })
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleDisplayPreferencesChanged() }
        }
    }

    private func removeWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { center.removeObserver($0) }
        workspaceObservers.removeAll()
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
            self.defaultsObserver = nil
        }
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
        stopPixelShiftTimer()
        resetPixelShift()
        lifecycleTask?.cancel()
        lifecycleGeneration += 1
        let generation = lifecycleGeneration

        guard superview != nil else {
            removeWorkspaceObservers()
            lifecycleTask = Task { @MainActor [weak self] in
                guard let self, self.lifecycleGeneration == generation else { return }
                await self.store.send(.viewDisappeared)
            }
            return
        }

        installWorkspaceObservers()
        // A new presentation builds a new function row, so the close box
        // hide has to be re-applied; the flag only guards within a session.
        systemCloseBoxHidden = false
        scheduleSystemCloseBoxHide()
        lifecycleTask = Task { @MainActor [weak self] in
            guard let self, self.lifecycleGeneration == generation else { return }
            await self.store.send(.viewAppeared(String(describing: TouchBarMetricsContainerView.self)))
            guard self.lifecycleGeneration == generation else { return }
            self.scheduleRebuildIfNeeded()
            self.updateVisibleValues()
            self.updateRunnerIfNeeded()
            self.observeStoreChanges()
            self.startRotationTimer()
            self.startPixelShiftTimer()
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

    /// Pixel Shift is enabled by default and can be changed in Touch Bar
    /// settings using the "TouchBarOLEDProtectionPixelShiftEnabled" key.
    /// A one-physical-pixel offset is applied to the complete custom content
    /// container, so stock-cell hit testing moves with the rendered content.
    private func startPixelShiftTimer() {
        guard superview != nil,
              isSessionActive,
              !isSystemSleeping,
              UserDefaults.standard.bool(forKey: TouchBarOLEDTheme.pixelShiftDefaultsKey),
              pixelShiftTimer == nil else { return }
        let timer = Timer(timeInterval: Self.pixelShiftInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advancePixelShift() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pixelShiftTimer = timer
    }

    private func stopPixelShiftTimer() {
        pixelShiftTimer?.invalidate()
        pixelShiftTimer = nil
    }

    private func handleDisplayPreferencesChanged() {
        if UserDefaults.standard.bool(forKey: TouchBarOLEDTheme.pixelShiftDefaultsKey) {
            startPixelShiftTimer()
        } else {
            stopPixelShiftTimer()
            resetPixelShift()
        }
        // Stock brightness changes only affect tint; update existing labels in place.
        updateVisibleValues()
    }

    private func advancePixelShift() {
        guard let window else { return }
        let scale = max(window.backingScaleFactor, 1)
        let pixel = 1 / scale
        let offsets: [(CGFloat, CGFloat)] = [
            (pixel, 0),
            (0, pixel),
            (-pixel, 0),
            (0, -pixel),
        ]
        let offset = offsets[pixelShiftIndex % offsets.count]
        pixelShiftIndex += 1
        contentCenterXConstraint.constant = offset.0
        contentCenterYConstraint.constant = offset.1
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    private func resetPixelShift() {
        pixelShiftIndex = 0
        contentCenterXConstraint.constant = 0
        contentCenterYConstraint.constant = 0
    }

    private func handleSessionInactive() {
        isSessionActive = false
        alphaValue = 0.55
        stopRotationTimer()
        stopPixelShiftTimer()
    }

    private func handleSessionActive() {
        isSessionActive = true
        if !isSystemSleeping {
            alphaValue = 1
            startRotationTimer()
            startPixelShiftTimer()
        }
    }

    private func handleSystemSleep() {
        isSystemSleeping = true
        stopRotationTimer()
        stopPixelShiftTimer()
    }

    private func handleSystemWake() {
        isSystemSleeping = false
        alphaValue = isSessionActive ? 1 : 0.55
        startRotationTimer()
        startPixelShiftTimer()
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
            _ = store.runnerBundleList
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
            let tint = TouchBarOLEDTheme.stockColor(for: indicator.direction)
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
                if field.stringValue != value.0 {
                    field.stringValue = value.0
                    // NSTextField's frame does not always follow a wider
                    // live value inside an NSStackView. Refit the control
                    // immediately so suffixes (K/M/B) are not clipped.
                    field.invalidateIntrinsicContentSize()
                    field.sizeToFit()
                    field.superview?.invalidateIntrinsicContentSize()
                    field.superview?.needsLayout = true
                }
                field.textColor = value.1
            } else if let imageView = view as? NSImageView,
                      let key = imageView.identifier?.rawValue,
                      let value = icons[key] {
                if imageView.image == nil || lastMetricIconSymbols[key] != value.0 {
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

        // Live labels can become wider after their stack slot was created.
        // Re-measure only stack slots whose member fitting width actually changed.
        for entry in stackViews where isInHierarchy(entry.view) {
            entry.view.invalidateIntrinsicContentSize()
            entry.view.needsLayout = true
            entry.view.layoutSubtreeIfNeeded()
            _ = entry.view.refreshMemberWidths()
        }

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
            || panel != lastPanel
            || runnerPickerPage != lastRunnerPickerPage
            || store.runnerBundleList.count != lastRunnerListCount
            || prioritizeStocks != lastPrioritizeStocks
            || showsStocks != lastShowsStocks
            || showsRunner != lastShowsRunner
            || hasRunner != lastHasRunner else {
            return
        }
        lastMetricStructure = metricStructure
        lastStockStructure = stockStructure
        lastExpandedID = expandedStockID
        lastPanel = panel
        lastRunnerPickerPage = runnerPickerPage
        lastRunnerListCount = store.runnerBundleList.count
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
            contentContainerView.addSubview(leadingStack)
            layoutConstraints = [
                leadingStack.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor, constant: Self.horizontalInset),
                leadingStack.centerYAnchor.constraint(equalTo: contentContainerView.centerYAnchor),
                leadingStack.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor, constant: -Self.horizontalInset),
            ]
            NSLayoutConstraint.activate(layoutConstraints)
            return
        }

        if panel != nil {
            // A control page owns the bar exactly like the stock detail does.
            runnerView.removeFromSuperview()
            panelStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            buildPanel()
            contentContainerView.addSubview(panelStack)
            layoutConstraints = [
                panelStack.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor, constant: Self.horizontalInset),
                panelStack.centerYAnchor.constraint(equalTo: contentContainerView.centerYAnchor),
                panelStack.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor, constant: -Self.horizontalInset),
            ]
            NSLayoutConstraint.activate(layoutConstraints)
            scheduleSystemCloseBoxHide()
            return
        }
        panelStack.removeFromSuperview()

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
            contentContainerView.addSubview(leadingStocksStack)
            layoutConstraints = [
                leadingStocksStack.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor, constant: Self.horizontalInset),
                leadingStocksStack.centerYAnchor.constraint(equalTo: contentContainerView.centerYAnchor),
            ]
            if !metricSlots.isEmpty {
                contentContainerView.addSubview(separatorView)
                contentContainerView.addSubview(scrollView)
                scrollView.documentView = metricsScrollStack
                sizeDocumentView(metricsScrollStack)
                layoutConstraints.append(contentsOf: [
                    separatorView.leadingAnchor.constraint(equalTo: leadingStocksStack.trailingAnchor, constant: Self.separatorGap),
                    separatorView.centerYAnchor.constraint(equalTo: contentContainerView.centerYAnchor),
                    scrollView.leadingAnchor.constraint(equalTo: separatorView.trailingAnchor, constant: Self.separatorGap),
                    scrollView.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor, constant: -Self.horizontalInset),
                    scrollView.centerYAnchor.constraint(equalTo: contentContainerView.centerYAnchor),
                    scrollView.heightAnchor.constraint(equalToConstant: Self.documentHeight),
                ])
            }
        } else {
            // Everything lives in the content container so Pixel Shift moves
            // hit-testing together with the pixels.
            contentContainerView.addSubview(leadingStack)
            layoutConstraints = [
                leadingStack.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor, constant: Self.horizontalInset),
                leadingStack.centerYAnchor.constraint(equalTo: contentContainerView.centerYAnchor),
            ]
            if showsStocks {
                contentContainerView.addSubview(separatorView)
                contentContainerView.addSubview(scrollView)
                scrollView.documentView = stocksScrollStack
                sizeDocumentView(stocksScrollStack)
                layoutConstraints.append(contentsOf: [
                    separatorView.leadingAnchor.constraint(equalTo: leadingStack.trailingAnchor, constant: Self.separatorGap),
                    separatorView.centerYAnchor.constraint(equalTo: contentContainerView.centerYAnchor),
                    scrollView.leadingAnchor.constraint(equalTo: separatorView.trailingAnchor, constant: Self.separatorGap),
                    scrollView.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor, constant: -Self.horizontalInset),
                    scrollView.centerYAnchor.constraint(equalTo: contentContainerView.centerYAnchor),
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
        let tint = TouchBarOLEDTheme.stockColor(for: indicator.direction)
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

        panel.addArrangedSubview(makeIconCell("chart.line.uptrend.xyaxis", tint: TouchBarOLEDTheme.stockColor(for: indicator.direction)))
        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.addArrangedSubview(makeTextCell(
            indicator.name,
            font: .systemFont(ofSize: 12, weight: .semibold),
            tint: TouchBarOLEDTheme.stockColor(for: indicator.direction),
            identifier: "stock:\(indicator.id.uuidString):detail-name"
        ))
        textStack.addArrangedSubview(makeTextCell(
            detailString(quote: quote),
            font: .monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            tint: TouchBarOLEDTheme.stockColor(for: indicator.direction),
            identifier: "stock:\(indicator.id.uuidString):detail-line"
        ))
        panel.addArrangedSubview(textStack)
        panel.addArrangedSubview(makeTextCell(
            String(format: "%+.2f%%", indicator.changePercent),
            font: .monospacedDigitSystemFont(ofSize: 14, weight: .semibold),
            tint: TouchBarOLEDTheme.stockColor(for: indicator.direction),
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

    /// Every symbol in the bar (metrics, stocks, placeholders, chevrons) uses
    /// this size, which matches the runner previews in the picker — the user
    /// found the original 12pt glyphs too small next to them.
    private static let iconPointSize: CGFloat = 18
    private static let iconBox: CGFloat = 22

    private func makeIconCell(_ systemName: String, tint: NSColor) -> NSImageView {
        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: Self.iconPointSize, weight: .regular))
        imageView.contentTintColor = tint
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: Self.iconBox).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: Self.iconBox).isActive = true
        return imageView
    }

    /// The brightness page's suns, matching the system control's differing
    /// glyph sizes at the two ends of the track.
    private func makeSunCell(_ systemName: String, pointSize: CGFloat, side: CGFloat) -> NSImageView {
        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .regular))
        imageView.contentTintColor = TouchBarOLEDTheme.controlFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: side).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: side).isActive = true
        return imageView
    }

    /// Finds the brightness track in the current panel, used to refresh its
    /// knob after a step or a tap changes the stored value.
    private func findTrack(in view: NSView) -> NSView? {
        if view is TouchBarBrightnessTrack { return view }
        for child in view.subviews {
            if let found = findTrack(in: child) { return found }
        }
        return nil
    }

    /// The separate close box beside the brightness card: the system draws a
    /// large gray disc with a white cross, so this draws the same instead of
    /// scaling a symbol (which looked small).
    private func makeCloseCell(identifier: String) -> NSView {
        let cell = CloseCircleView()
        cell.identifier = NSUserInterfaceItemIdentifier(identifier)
        cell.translatesAutoresizingMaskIntoConstraints = false
        cell.widthAnchor.constraint(equalToConstant: CloseCircleView.side).isActive = true
        cell.heightAnchor.constraint(equalToConstant: CloseCircleView.side).isActive = true
        let tap = NSClickGestureRecognizer(target: self, action: #selector(panelCellTapped(_:)))
        cell.addGestureRecognizer(tap)
        return cell
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
        TouchBarOLEDTheme.stockColor(for: direction)
    }

    // MARK: - Control panel

    /// Nine previews per page: 48pt cells plus both paging arrows fit the
    /// 597pt usable width. Previews are fitted inside the 46×22pt box so a
    /// wide runner (Newton's cradle) cannot overlap its neighbours — its
    /// vertical strings looked like separators between the cells.
    private static let runnerPickerPageSize = 9
    private static let runnerCellWidth: CGFloat = 48
    private static let runnerPreviewSize = NSSize(width: 46, height: 22)
    /// Measured from the system brightness control (2px/pt screenshot): the
    /// card is 360×28pt on a 30pt row, its track 202pt long and 4pt thick,
    /// the knob 30pt square, the close box a 22pt circle.
    private static let brightnessCardWidth: CGFloat = 360
    private static let brightnessCardHeight: CGFloat = 26
    private static let brightnessCardCornerRadius: CGFloat = 8
    private static let brightnessSunBoxSmall: CGFloat = 16
    private static let brightnessSunBoxLarge: CGFloat = 18
    private static let brightnessGap: CGFloat = 19
    /// The runner menu shows a glyph over a label. The row is 30pt tall, so
    /// the icon box is 15pt high with room for the 9pt title beneath it.
    private static let menuIconBox = NSSize(width: 40, height: 15)
    private static let menuIconPointSize: CGFloat = 13
    private static let menuCellMinWidth: CGFloat = 46
    private static let menuCellHeight: CGFloat = 30
    private static let menuCellGap: CGFloat = 16

    private func buildPanel() {
        switch panel {
        case .menu:
            buildMenuPanel()
        case .runnerPicker:
            buildRunnerPickerPanel()
        case .brightness:
            buildBrightnessPanel()
        case nil:
            break
        }
    }

    /// The runner's menu: three labeled cells, starting at the bar's leading
    /// edge. Tapping a cell is captured by a recognizer on the cell itself,
    /// so the identifier carries the action.
    private func buildMenuPanel() {
        let items: [(id: String, symbol: String, image: NSImage?, title: String)] = [
            (
                "panel:menu:runner",
                "figure.run",
                store.touchBarRunnerFrames.first.map {
                    Self.previewImage(
                        $0,
                        box: Self.menuIconBox,
                        isTemplate: store.touchBarRunnerIsTemplate,
                        tint: TouchBarOLEDTheme.dynamicValue
                    )
                },
                String(localized: "touchBarPanelRunner", bundle: .module)
            ),
            (
                "panel:menu:brightness",
                "sun.max",
                nil,
                String(localized: "touchBarPanelBrightness", bundle: .module)
            ),
            (
                "panel:menu:hide",
                "xmark.circle",
                nil,
                String(localized: "touchBarPanelHide", bundle: .module)
            ),
        ]
        for (index, item) in items.enumerated() {
            if index > 0 {
                panelStack.addArrangedSubview(Self.fixedSpace(width: Self.menuCellGap))
            }
            panelStack.addArrangedSubview(makeMenuCell(
                identifier: item.id,
                symbol: item.symbol,
                image: item.image,
                title: item.title
            ))
        }
        panelStack.addArrangedSubview(Self.spacer())
    }

    private func buildRunnerPickerPanel() {
        let runners = store.runnerBundleList
        let pageSize = Self.runnerPickerPageSize
        let pageCount = max(1, (runners.count + pageSize - 1) / pageSize)
        let page = min(max(runnerPickerPage, 0), pageCount - 1)
        runnerPickerPage = page

        panelStack.addArrangedSubview(makeChevronCell(symbol: "chevron.left", identifier: "panel:back"))
        if page > 0 {
            panelStack.addArrangedSubview(makeChevronCell(symbol: "chevron.left", identifier: "panel:page:prev"))
        }
        let currentRunnerID = store.currentRunnerID
        let pageRunners = Array(runners.dropFirst(page * pageSize).prefix(pageSize))
        if pageRunners.isEmpty {
            panelStack.addArrangedSubview(makeTextCell(
                "—",
                font: .systemFont(ofSize: 10),
                tint: TouchBarOLEDTheme.dynamicValue
            ))
        }
        for runnerBundle in pageRunners {
            panelStack.addArrangedSubview(makeRunnerCell(
                bundle: runnerBundle,
                isCurrent: runnerBundle.runner.id == currentRunnerID
            ))
        }
        if page < pageCount - 1 {
            panelStack.addArrangedSubview(makeChevronCell(symbol: "chevron.right", identifier: "panel:page:next"))
        }
        panelStack.addArrangedSubview(Self.spacer())
    }

    /// Mirrors the system brightness control: a compact rounded card holding a
    /// small sun, the native slider and a large sun; the close box is a
    /// separate control beside the card, exactly like the system's panel.
    private func buildBrightnessPanel() {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = TouchBarOLEDTheme.panelCard.cgColor
        card.layer?.cornerRadius = Self.brightnessCardCornerRadius
        card.translatesAutoresizingMaskIntoConstraints = false
        card.widthAnchor.constraint(equalToConstant: Self.brightnessCardWidth).isActive = true
        card.heightAnchor.constraint(equalToConstant: Self.brightnessCardHeight).isActive = true

        let smallSun = makeSunCell("sun.min", pointSize: 14, side: Self.brightnessSunBoxSmall)
        smallSun.identifier = NSUserInterfaceItemIdentifier("panel:brightness:minus")
        let minusTap = NSClickGestureRecognizer(target: self, action: #selector(brightnessStepTapped(_:)))
        smallSun.addGestureRecognizer(minusTap)
        let bigSun = makeSunCell("sun.max", pointSize: 16, side: Self.brightnessSunBoxLarge)
        bigSun.identifier = NSUserInterfaceItemIdentifier("panel:brightness:plus")
        let plusTap = NSClickGestureRecognizer(target: self, action: #selector(brightnessStepTapped(_:)))
        bigSun.addGestureRecognizer(plusTap)
        let track = TouchBarBrightnessTrack()
        track.minimum = TouchBarStockBrightness.minimum
        track.maximum = TouchBarStockBrightness.maximum
        track.value = TouchBarOLEDTheme.stockBrightness
        track.translatesAutoresizingMaskIntoConstraints = false
        let tap = NSClickGestureRecognizer(target: self, action: #selector(brightnessTrackTapped(_:)))
        track.addGestureRecognizer(tap)
        card.addSubview(smallSun)
        card.addSubview(track)
        card.addSubview(bigSun)
        NSLayoutConstraint.activate([
            smallSun.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 28),
            smallSun.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            track.leadingAnchor.constraint(equalTo: smallSun.trailingAnchor, constant: Self.brightnessGap),
            track.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            track.heightAnchor.constraint(equalToConstant: Self.brightnessCardHeight),
            // 232pt bounds render the system control's 202pt track once the
            // knob's half-width insets are applied.
            track.widthAnchor.constraint(equalToConstant: 232),
            bigSun.leadingAnchor.constraint(equalTo: track.trailingAnchor, constant: Self.brightnessGap),
            bigSun.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -28),
            bigSun.centerYAnchor.constraint(equalTo: card.centerYAnchor),
        ])
        // Every control page starts at the bar's leading edge, like the rest
        // of the app's content.
        panelStack.addArrangedSubview(card)
        panelStack.addArrangedSubview(Self.fixedSpace(width: 22))
        panelStack.addArrangedSubview(makeCloseCell(identifier: "panel:done"))
        panelStack.addArrangedSubview(Self.spacer())
    }

    /// The same key the settings slider writes, so both stay in sync and the
    /// stock colors recolor in place with their hue preserved.
    private func applyStockBrightness(_ value: Double) {
        TouchBarOLEDTheme.setStockBrightness(value)
        if let track = findTrack(in: self) as? TouchBarBrightnessTrack {
            track.value = TouchBarOLEDTheme.stockBrightness
        }
        updateVisibleValues()
    }

    @objc private func brightnessTrackTapped(_ sender: NSClickGestureRecognizer) {
        guard let track = sender.view as? TouchBarBrightnessTrack else { return }
        applyStockBrightness(track.value(at: sender.location(in: track)))
    }

    @objc private func brightnessStepTapped(_ sender: NSClickGestureRecognizer) {
        guard let identifier = sender.view?.identifier?.rawValue else { return }
        let step = identifier == "panel:brightness:plus"
            ? TouchBarStockBrightness.step
            : -TouchBarStockBrightness.step
        applyStockBrightness(TouchBarOLEDTheme.stockBrightness + step)
    }

    /// A menu entry: a glyph above its 9pt label, so the action is named and
    /// still easy to hit on the narrow bar.
    private func makeMenuCell(
        identifier: String,
        symbol: String,
        image: NSImage?,
        title: String
    ) -> NSView {
        let cell = NSStackView()
        cell.orientation = .vertical
        cell.alignment = .centerX
        cell.spacing = 1
        cell.identifier = NSUserInterfaceItemIdentifier(identifier)
        cell.translatesAutoresizingMaskIntoConstraints = false
        cell.widthAnchor.constraint(
            greaterThanOrEqualToConstant: Self.menuCellMinWidth
        ).isActive = true
        cell.setContentHuggingPriority(.required, for: .horizontal)
        cell.setContentCompressionResistancePriority(.required, for: .horizontal)

        let imageView = NSImageView()
        imageView.image = image ?? NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: Self.menuIconPointSize, weight: .regular))
        imageView.contentTintColor = TouchBarOLEDTheme.dynamicValue
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: Self.menuIconBox.width).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: Self.menuIconBox.height).isActive = true
        cell.addArrangedSubview(imageView)
        cell.addArrangedSubview(makeTextCell(
            title,
            font: .systemFont(ofSize: 9, weight: .medium),
            tint: TouchBarOLEDTheme.dynamicValue
        ))

        let tap = NSClickGestureRecognizer(target: self, action: #selector(panelCellTapped(_:)))
        cell.addGestureRecognizer(tap)
        return cell
    }

    private func makeChevronCell(symbol: String, identifier: String) -> NSView {
        let cell = NSStackView()
        cell.identifier = NSUserInterfaceItemIdentifier(identifier)
        cell.addArrangedSubview(makeIconCell(symbol, tint: TouchBarOLEDTheme.dynamicValue))
        cell.setContentHuggingPriority(.required, for: .horizontal)
        cell.setContentCompressionResistancePriority(.required, for: .horizontal)
        let tap = NSClickGestureRecognizer(target: self, action: #selector(panelCellTapped(_:)))
        cell.addGestureRecognizer(tap)
        return cell
    }

    /// One runner in the picker: its preview image only. The names are
    /// omitted — the previews are what tell the runners apart — and the
    /// current runner is marked by a soft rounded background.
    private func makeRunnerCell(bundle: RunnerBundle, isCurrent: Bool) -> NSView {
        let cell = NSView()
        cell.identifier = NSUserInterfaceItemIdentifier("panel:runner:\(bundle.runner.id)")
        cell.translatesAutoresizingMaskIntoConstraints = false
        cell.widthAnchor.constraint(equalToConstant: Self.runnerCellWidth).isActive = true
        cell.heightAnchor.constraint(equalToConstant: Self.menuCellHeight).isActive = true
        cell.setContentHuggingPriority(.required, for: .horizontal)
        cell.setContentCompressionResistancePriority(.required, for: .horizontal)
        if isCurrent {
            cell.wantsLayer = true
            cell.layer?.backgroundColor = TouchBarOLEDTheme.panelCard.cgColor
            cell.layer?.cornerRadius = 7
        }

        let tint = isCurrent ? TouchBarOLEDTheme.controlFill : TouchBarOLEDTheme.dynamicValue
        let imageView = NSImageView()
        imageView.image = Self.thumbnail(of: bundle, box: Self.runnerPreviewSize, tint: tint)
            ?? NSImage(
                systemSymbolName: "questionmark.square.dashed",
                accessibilityDescription: nil
            )?.withSymbolConfiguration(.init(pointSize: 18, weight: .regular))
        imageView.contentTintColor = tint
        imageView.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        let tap = NSClickGestureRecognizer(target: self, action: #selector(panelCellTapped(_:)))
        cell.addGestureRecognizer(tap)
        return cell
    }

    private static func thumbnail(
        of bundle: RunnerBundle,
        box: NSSize,
        tint: NSColor
    ) -> NSImage? {
        let frame: Frame
        switch bundle.displayFormat {
        case let .thumbnail(value):
            frame = value
        case let .keyFrameAnimation(frames):
            guard let first = frames.first else { return nil }
            frame = first
        }
        let image: NSImage?
        switch frame {
        case let .preset(resourceName):
            image = NSImage(resource: .init(name: resourceName, bundle: .module))
        case let .custom(data):
            image = NSImage(data: data)
        case .broken:
            image = nil
        }
        guard let image else { return nil }
        return previewImage(
            image,
            box: box,
            isTemplate: bundle.runner.isTemplate,
            tint: tint
        )
    }

    /// Fits a runner frame into `box` (preserving its aspect, never enlarging
    /// past it). Preset frames are monochrome masks — the menu bar tints them
    /// through a mask layer — so drawing them as-is leaves an invisible black
    /// silhouette on the bar; template runners are therefore filled with the
    /// tint while custom runners keep their own colours.
    private static func previewImage(
        _ image: NSImage,
        box: NSSize,
        isTemplate: Bool,
        tint: NSColor
    ) -> NSImage {
        let scaled = scaledRunnerImage(image, box: box, isTemplate: isTemplate)
        guard isTemplate else { return scaled }
        return tinted(scaled, color: tint)
    }

    private static func scaledRunnerImage(
        _ image: NSImage,
        box: NSSize,
        isTemplate: Bool
    ) -> NSImage {
        let copy = image.copy() as! NSImage
        let size = image.size
        let scale = size.width > 0 && size.height > 0
            ? min(box.width / size.width, box.height / size.height)
            : 1
        copy.size = NSSize(width: size.width * scale, height: size.height * scale)
        copy.isTemplate = isTemplate
        return copy
    }

    /// Fills the image's alpha silhouette with `color`.
    ///
    /// Drawn through a pixel-sized `CGContext`: tinting a fractionally sized
    /// image inside a `lockFocus` context left a faint one-pixel column along
    /// the right edge (the fill's antialiased boundary survived
    /// `.destinationIn`), which read as a vertical separator between the
    /// picker's runners.
    private static func tinted(_ image: NSImage, color: NSColor) -> NSImage {
        let points = image.size
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(
                  data: nil,
                  width: max(1, Int((points.width * 2).rounded())),
                  height: max(1, Int((points.height * 2).rounded())),
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return image
        }
        let rect = CGRect(
            x: 0,
            y: 0,
            width: context.width,
            height: context.height
        )
        context.setFillColor(color.cgColor)
        context.fill(rect)
        context.setBlendMode(.destinationIn)
        context.interpolationQuality = .high
        context.draw(source, in: rect)
        guard let output = context.makeImage() else { return image }
        return NSImage(cgImage: output, size: points)
    }

    /// An elastic gap that absorbs every leftover point, so the content before
    /// it stays hard against the leading edge. Its hugging priority is
    /// deliberately below the default (250): otherwise AppKit hands the slack
    /// to the icon cells as well and the row drifts.
    private static func spacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        return spacer
    }

    /// A fixed gap inside a stack, used between the brightness card and its
    /// close box so they read as one control.
    private static func fixedSpace(width: CGFloat) -> NSView {
        let space = NSView()
        space.translatesAutoresizingMaskIntoConstraints = false
        space.widthAnchor.constraint(equalToConstant: width).isActive = true
        space.setContentHuggingPriority(.required, for: .horizontal)
        space.setContentCompressionResistancePriority(.required, for: .horizontal)
        return space
    }

    // MARK: - System close box

    /// The system-modal presentation draws its own close box, which the bar
    /// does not want (the runner menu carries a hide control instead). It is
    /// a sibling stack left of this view inside the function row, in our own
    /// process, so it can be hidden — but the row is rebuilt on every present,
    /// hence the re-apply.
    private func scheduleSystemCloseBoxHide() {
        guard !systemCloseBoxHidden else { return }
        DispatchQueue.main.async { [weak self] in
            self?.hideSystemCloseBox()
        }
    }

    private func hideSystemCloseBox() {
        var ancestor: NSView? = superview
        var host: NSView?
        var depth = 0
        while let view = ancestor, depth < 6 {
            if String(describing: type(of: view)) == "NSFunctionRowBackgroundColorView" {
                host = view
                break
            }
            ancestor = view.superview
            depth += 1
        }
        guard let host else { return }
        let ownFrame = convert(bounds, to: host)
        for sibling in host.subviews where sibling !== self {
            guard String(describing: type(of: sibling)) == "NSStackView",
                  let button = sibling.subviews.compactMap({ $0 as? NSButton }).first,
                  sibling.frame.maxX <= ownFrame.minX + 1 else {
                continue
            }
            button.isHidden = true
            sibling.isHidden = true
            systemCloseBoxHidden = true
        }
    }

    // MARK: - Rotation

    /// Advances each active stack one member. Inactive presentation copies
    /// are no longer built, so every entry here is a live candidate.
    private func rotateStacks() {
        guard expandedStockID == nil, panel == nil else { return }
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

    @objc private func runnerTapped(_ sender: NSClickGestureRecognizer) {
        guard expandedStockID == nil else { return }
        panel = .menu
        scheduleRebuildIfNeeded()
        updateVisibleValues()
    }

    @objc private func panelCellTapped(_ sender: NSClickGestureRecognizer) {
        guard let identifier = sender.view?.identifier?.rawValue else { return }
        switch identifier {
        case "panel:menu:runner":
            runnerPickerPage = 0
            panel = .runnerPicker
        case "panel:menu:brightness":
            panel = .brightness
        case "panel:menu:hide":
            panel = nil
            Task { await store.send(.touchBarMinimizeRequested) }
        case "panel:back":
            panel = panel == .menu ? nil : .menu
        case "panel:done":
            // The brightness page closes straight back to the main bar, like
            // the system brightness control's close box.
            panel = nil
        case "panel:page:prev":
            runnerPickerPage = max(0, runnerPickerPage - 1)
        case "panel:page:next":
            runnerPickerPage += 1
        default:
            guard identifier.hasPrefix("panel:runner:") else { return }
            let runnerID = String(identifier.dropFirst("panel:runner:".count))
            guard let runner = store.runnerBundleList
                .first(where: { $0.runner.id == runnerID })?.runner else {
                return
            }
            // Selecting closes the panel: the new runner is the feedback.
            panel = nil
            Task { await store.send(.runnerSelectionRequested(runner)) }
        }
        scheduleRebuildIfNeeded()
        updateVisibleValues()
    }

    @objc private func detailPanelTapped(_ sender: NSClickGestureRecognizer) {
        expandedStockID = nil
        scheduleRebuildIfNeeded()
    }
}

/// The brightness track's visuals: hairline track, blue fill and the white
/// knob that grows while it is touched. Input is handled by a click recognizer
/// on the view (see the container): the Touch Bar reports third-party content
/// as taps, while Apple's own brightness item reads the private gesture stream.
final class TouchBarBrightnessTrack: NSView {
    private static let knobWidth: CGFloat = 30
    private static let knobIdleHeight: CGFloat = 20
    private static let knobRadius: CGFloat = 7
    private static let trackHeight: CGFloat = 4

    var minimum: Double = 0.7
    var maximum: Double = 1.5

    var value: Double = 1.0 {
        didSet {
            value = min(max(value, minimum), maximum)
            needsDisplay = true
        }
    }

    private var progress: CGFloat {
        let span = maximum - minimum
        guard span > 0 else { return 1 }
        return CGFloat((value - minimum) / span)
    }

    /// The value at a point inside the view, matching where the knob's center
    /// sits on the track.
    func value(at point: NSPoint) -> Double {
        let inset = Self.knobWidth / 2
        let trackWidth = max(bounds.width - inset * 2, 1)
        let fraction = min(max((point.x - inset) / trackWidth, 0), 1)
        return minimum + Double(fraction) * (maximum - minimum)
    }

    override func draw(_ dirtyRect: NSRect) {
        let inset = Self.knobWidth / 2
        let centerY = bounds.midY

        let trackRect = NSRect(
            x: inset,
            y: centerY - Self.trackHeight / 2,
            width: max(bounds.width - inset * 2, 1),
            height: Self.trackHeight
        )
        TouchBarOLEDTheme.sliderTrack.setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: 1.5, yRadius: 1.5).fill()

        let knobCenterX = trackRect.minX + progress * trackRect.width
        let filledRect = NSRect(
            x: trackRect.minX,
            y: trackRect.minY,
            width: max(knobCenterX - trackRect.minX, 0),
            height: Self.trackHeight
        )
        TouchBarOLEDTheme.sliderFill.setFill()
        NSBezierPath(roundedRect: filledRect, xRadius: 1.5, yRadius: 1.5).fill()

        let knobRect = NSRect(
            x: knobCenterX - Self.knobWidth / 2,
            y: centerY - Self.knobIdleHeight / 2,
            width: Self.knobWidth,
            height: Self.knobIdleHeight
        )
        TouchBarOLEDTheme.sliderKnob.setFill()
        NSBezierPath(
            roundedRect: knobRect,
            xRadius: Self.knobRadius,
            yRadius: Self.knobRadius
        ).fill()
    }
}

/// The brightness page's close box: a large gray disc with a white cross,
/// drawn rather than scaled from a symbol so it matches the system control.
final class CloseCircleView: NSView {
    static let side: CGFloat = 26
    private static let diameter: CGFloat = 24
    private static let crossArm: CGFloat = 4.2
    private static let crossLineWidth: CGFloat = 1.8

    override func draw(_ dirtyRect: NSRect) {
        let diameter = Self.diameter
        let disc = NSRect(
            x: (bounds.width - diameter) / 2,
            y: (bounds.height - diameter) / 2,
            width: diameter,
            height: diameter
        )
        TouchBarOLEDTheme.closeBox.setFill()
        NSBezierPath(ovalIn: disc).fill()

        let center = NSPoint(x: disc.midX, y: disc.midY)
        let arm = Self.crossArm
        TouchBarOLEDTheme.sliderKnob.setStroke()
        for sign in [CGFloat(1), -1] {
            let path = NSBezierPath()
            path.lineWidth = Self.crossLineWidth
            path.lineCapStyle = .round
            path.move(to: NSPoint(x: center.x - arm, y: center.y + sign * arm))
            path.line(to: NSPoint(x: center.x + arm, y: center.y - sign * arm))
            path.stroke()
        }
    }
}
