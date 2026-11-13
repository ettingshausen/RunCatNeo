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
    private var lastMetricSlots: [TouchBarMetricSlot] = []
    private var lastStockSlots: [TouchBarStockSlot] = []
    private var lastExpandedID: UUID?
    private var lastPrioritizeStocks: Bool?
    private var lastShowsStocks = false
    private var lastShowsRunner: Bool?
    private var lastHasRunner = false
    private var lastRunnerVersion = 0
    private var lastRunnerSpeed: Float = 1
    private var pollTimer: Timer?
    private var rotationTimer: Timer?
    private var rebuildPending = false
    private var layoutConstraints: [NSLayoutConstraint] = []
    /// Rotation phase per stack slot. Both copies of a stack (the pinned one
    /// and the clipping one) share the phase and advance together.
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
        layer?.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 1).cgColor
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
        separatorView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        // A separator without a size renders as nothing.
        NSLayoutConstraint.activate([
            separatorView.widthAnchor.constraint(equalToConstant: 1),
            separatorView.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: Self.barWidth, height: Self.height)
    }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        pollTimer?.invalidate()
        rotationTimer?.invalidate()
        guard superview != nil else { return }
        Task { @MainActor [weak self] in
            await self?.store.send(.viewAppeared(String(describing: TouchBarMetricsContainerView.self)))
        }
        // This callback runs inside the Touch Bar's layout pass; view
        // mutations must be deferred or AppKit crashes on the exception.
        scheduleRebuildIfNeeded()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleRebuildIfNeeded()
                self?.updateRunnerIfNeeded()
            }
        }
        // `.common` keeps the rotation ticking while a gesture is tracking.
        let rotationTimer = Timer(timeInterval: Self.rotationInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.rotateStacks() }
        }
        RunLoop.main.add(rotationTimer, forMode: .common)
        self.rotationTimer = rotationTimer
    }

    /// Compares the store's slot snapshots and, when they drifted, asks for a
    /// deferred rebuild. The rebuild never runs inside a layout pass, where
    /// mutating the hierarchy crashes AppKit.
    private func scheduleRebuildIfNeeded() {
        let metricSlots = store.touchBarMetricSlots
        let stockSlots = store.touchBarStockSlots
        let prioritizeStocks = store.touchBarConfiguration.prioritizeStocks
        let showsStocks = store.stockConfiguration.stocks.isEmpty == false
        let showsRunner = store.touchBarConfiguration.showsRunner
        let hasRunner = store.touchBarRunnerVersion > 0
        guard metricSlots != lastMetricSlots
            || stockSlots != lastStockSlots
            || expandedStockID != lastExpandedID
            || prioritizeStocks != lastPrioritizeStocks
            || showsStocks != lastShowsStocks
            || showsRunner != lastShowsRunner
            || hasRunner != lastHasRunner else {
            return
        }
        lastMetricSlots = metricSlots
        lastStockSlots = stockSlots
        lastExpandedID = expandedStockID
        lastPrioritizeStocks = prioritizeStocks
        lastShowsStocks = showsStocks
        lastShowsRunner = showsRunner
        lastHasRunner = hasRunner
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

        populateMetrics(into: leadingStack, slots: metricSlots)
        populateStocks(into: leadingStocksStack, slots: stockSlots)
        populateMetrics(into: metricsScrollStack, slots: metricSlots)
        populateStocks(into: stocksScrollStack, slots: stockSlots)
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
            stack.addArrangedSubview(makeIconCell("moon.zzz", tint: .white))
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
        cell.addArrangedSubview(makeIconCell(indicator.systemIcon, tint: .white))
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
                tint: .white
            ))
            column.addArrangedSubview(makeTextCell(
                secondaryText,
                font: .monospacedDigitSystemFont(ofSize: 8, weight: .regular),
                tint: .white
            ))
            cell.addArrangedSubview(column)
        } else {
            cell.addArrangedSubview(makeTextCell(
                indicator.primaryText,
                font: .monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                tint: .white
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
            tint: tint
        ))
        cell.addArrangedSubview(makeTextCell(
            String(format: "%+.2f%%", indicator.changePercent),
            font: .monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            tint: tint
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
            tint: color(for: indicator.direction)
        ))
        textStack.addArrangedSubview(makeTextCell(
            detailString(quote: quote),
            font: .monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            tint: color(for: indicator.direction)
        ))
        panel.addArrangedSubview(textStack)
        panel.addArrangedSubview(makeTextCell(
            String(format: "%+.2f%%", indicator.changePercent),
            font: .monospacedDigitSystemFont(ofSize: 14, weight: .semibold),
            tint: color(for: indicator.direction)
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

    private func makeTextCell(_ text: String, font: NSFont, tint: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = tint
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
        switch direction {
        case .up: NSColor.red
        case .down: NSColor.green
        case .flat: NSColor.white
        }
    }

    // MARK: - Rotation

    /// Advances every visible stack one member. A slot exists twice in the
    /// bookkeeping (once pinned, once in the clipping view), so the phase moves
    /// once per slot and only the attached copy animates.
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

    /// The same slot is built for both the pinned and the clipping collection;
    /// only the copy that actually hangs under this view should animate.
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
