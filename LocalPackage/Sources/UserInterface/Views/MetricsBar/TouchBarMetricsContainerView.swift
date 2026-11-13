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
/// entries and metrics fit instead. Tapping a stock swaps the whole bar for
/// its detail panel.
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

    private var expandedStockID: UUID?
    private var lastSystemIndicators: [TouchBarIndicator] = []
    private var lastStockIndicators: [StockIndicator] = []
    private var lastExpandedID: UUID?
    private var lastPrioritizeStocks: Bool?
    private var lastShowsStocks = false
    private var pollTimer: Timer?
    private var rebuildPending = false
    private var layoutConstraints: [NSLayoutConstraint] = []

    /// The system-modal bar's viewport is narrower than the DFR display: on a
    /// 1085pt Touch Bar the host gives the bar 621pt and clips anything wider
    /// (measured from `NSTouchBarView`'s frame), so the item must request
    /// exactly that or its trailing content is cut off.
    static let barWidth: CGFloat = 621
    static let height: CGFloat = 28
    private static let documentHeight: CGFloat = height - 4
    private static let horizontalInset: CGFloat = 12
    private static let separatorGap: CGFloat = 10

    public init(_ appDependencies: AppDependencies) {
        store = MetricsBar(appDependencies)
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
        guard superview != nil else { return }
        Task { @MainActor [weak self] in
            await self?.store.send(.viewAppeared(String(describing: TouchBarMetricsContainerView.self)))
        }
        // This callback runs inside the Touch Bar's layout pass; view
        // mutations must be deferred or AppKit crashes on the exception.
        scheduleRebuildIfNeeded()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRebuildIfNeeded() }
        }
    }

    /// Compares the store's indicator snapshots and, when they drifted, asks
    /// for a deferred rebuild. The rebuild never runs inside a layout pass,
    /// where mutating the hierarchy crashes AppKit.
    private func scheduleRebuildIfNeeded() {
        let systemIndicators = store.touchBarIndicators
        let stockIndicators = store.stockIndicators
        let prioritizeStocks = store.touchBarConfiguration.prioritizeStocks
        let showsStocks = store.stockConfiguration.stocks.isEmpty == false
        guard systemIndicators != lastSystemIndicators
            || stockIndicators != lastStockIndicators
            || expandedStockID != lastExpandedID
            || prioritizeStocks != lastPrioritizeStocks
            || showsStocks != lastShowsStocks else {
            return
        }
        lastSystemIndicators = systemIndicators
        lastStockIndicators = stockIndicators
        lastExpandedID = expandedStockID
        lastPrioritizeStocks = prioritizeStocks
        lastShowsStocks = showsStocks
        guard !rebuildPending else { return }
        rebuildPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            rebuildPending = false
            rebuild(
                systemIndicators: store.touchBarIndicators,
                stockIndicators: store.stockIndicators,
                prioritizeStocks: store.touchBarConfiguration.prioritizeStocks,
                showsStocks: store.stockConfiguration.stocks.isEmpty == false
            )
        }
    }

    /// Relays out the bar: the prioritized group hugs its content at the
    /// leading edge, the other group fills a scroll view in the remaining
    /// width. Only the views a state needs are in the hierarchy: an unused
    /// separator would otherwise keep drawing its old frame.
    private func rebuild(
        systemIndicators: [TouchBarIndicator],
        stockIndicators: [StockIndicator],
        prioritizeStocks: Bool,
        showsStocks: Bool
    ) {
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

        populateMetrics(into: leadingStack, indicators: systemIndicators)
        populateStocks(into: leadingStocksStack, indicators: stockIndicators)
        populateMetrics(into: metricsScrollStack, indicators: systemIndicators)
        populateStocks(into: stocksScrollStack, indicators: stockIndicators)

        if prioritizeStocks && showsStocks {
            addSubview(leadingStocksStack)
            layoutConstraints = [
                leadingStocksStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalInset),
                leadingStocksStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            ]
            if !systemIndicators.isEmpty {
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

    private func populateMetrics(into stack: NSStackView, indicators: [TouchBarIndicator]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if indicators.isEmpty {
            stack.addArrangedSubview(makeIconCell("moon.zzz", tint: .white))
            return
        }
        for indicator in indicators {
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
            stack.addArrangedSubview(cell)
        }
    }

    private func populateStocks(into stack: NSStackView, indicators: [StockIndicator]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for indicator in indicators {
            stack.addArrangedSubview(makeStockCell(for: indicator))
        }
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
