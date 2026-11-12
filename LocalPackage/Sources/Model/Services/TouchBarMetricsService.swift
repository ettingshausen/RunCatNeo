/*
 TouchBarMetricsService.swift
 Model

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

/// Presents the metrics bar on the Touch Bar: a small anchor item persists in
/// the Control Strip and the full-width bar is presented system-modally on
/// top of the frontmost app's content via the private DFRFoundation API.
@MainActor
public final class TouchBarMetricsService: NSObject, NSTouchBarDelegate {
    /// Composition hook: the app target injects a builder for the metrics
    /// content view (SwiftUI content lives in UserInterface, invisible from
    /// Model). Returning an empty view keeps the bar presentable without one.
    public static var metricsContentViewProvider: (@MainActor (AppDependencies) -> NSView)?

    /// Evaluated lazily once; DFR hardware does not appear or vanish at runtime.
    public static let isTouchBarHardwareAvailable = TouchBarClient.liveValue.hasHardware()

    private static let ownBundleIdentifier = Bundle.main.bundleIdentifier ?? ""

    private static let trayItemIdentifier = NSTouchBarItem.Identifier("com.kyome.Neo.RunCat.touchBar.trayItem")
    private static let metricsItemIdentifier = NSTouchBarItem.Identifier("com.kyome.Neo.RunCat.touchBar.metricsItem")
    private static let collapseItemIdentifier = NSTouchBarItem.Identifier("com.kyome.Neo.RunCat.touchBar.collapseItem")

    enum Decision {
        case present
        case minimize
        case none
    }

    private let appDependencies: AppDependencies
    private let appStateClient: AppStateClient
    private let logService: LogService
    private let nsWorkspaceClient: NSWorkspaceClient
    private let touchBarClient: TouchBarClient
    private let userDefaultsRepository: UserDefaultsRepository

    private var touchBarConfiguration = TouchBarConfiguration.default
    private var showsMetricsBarOnTouchBar = true
    private var touchBar: NSTouchBar?
    private var trayItem: NSCustomTouchBarItem?
    private var isPresented = false
    private var frontmostApplicationInfo: FrontmostApplicationInfo?
    private var task: Task<Void, Never>?

    public init(_ appDependencies: AppDependencies) {
        self.appDependencies = appDependencies
        self.appStateClient = appDependencies.appStateClient
        self.logService = .init(appDependencies)
        self.nsWorkspaceClient = appDependencies.nsWorkspaceClient
        self.touchBarClient = appDependencies.touchBarClient
        self.userDefaultsRepository = .init(appDependencies.userDefaultsClient)
    }

    public func start() {
        let selectorsAvailable = touchBarClient.arePrivateSelectorsAvailable()
        let hardwareAvailable = Self.isTouchBarHardwareAvailable
        logService.notice(.touchBarSetup(
            step: "guards",
            detail: "selectors=\(selectorsAvailable) hardware=\(hardwareAvailable)"
        ))
        guard selectorsAvailable else { return }
        guard hardwareAvailable else { return }
        frontmostApplicationInfo = nsWorkspaceClient.frontmostApplication()
        if let info = frontmostApplicationInfo, info.bundleIdentifier != Self.ownBundleIdentifier {
            appStateClient.withLock { $0.lastExternalFrontmostApplication = info }
        }
        logService.notice(.touchBarSetup(step: "frontmost", detail: frontmostApplicationInfo?.bundleIdentifier ?? "nil"))
        setupTouchBar()
        reloadConfiguration()
        task = Task.immediate { [weak self] in
            await self?.observe()
        }
        applyCurrentDecision(trigger: .started)
    }

    public func stop() {
        task?.cancel()
        task = nil
        if let touchBar, isPresented {
            _ = touchBarClient.dismissSystemModal(touchBar)
        }
        if let trayItem {
            _ = touchBarClient.removeSystemTrayItem(trayItem)
        }
        isPresented = false
        trayItem = nil
        touchBar = nil
    }

    func emitConfigurationChange() {
        appStateClient.send(\.touchBarConfigurationChanges, ())
    }

    // MARK: - Presentation decision

    /// What caused the decision to be re-evaluated. A mode change must be
    /// applied immediately, while a frontmost-app switch must never undo a bar
    /// the user expanded by hand.
    enum Trigger {
        case started
        case configurationChanged
        case frontmostChanged
    }

    static func evaluate(
        configuration: TouchBarConfiguration,
        isEnabled: Bool,
        isHardwareAvailable: Bool,
        frontmostBundleIdentifier: String?,
        isPresented: Bool,
        trigger: Trigger
    ) -> Decision {
        guard isEnabled, isHardwareAvailable else {
            return isPresented ? .minimize : .none
        }
        switch configuration.mode {
        case .anchorOnly:
            // The bar is user-driven: only starting or switching modes forces
            // it closed, so a manual expansion survives app switches.
            switch trigger {
            case .frontmostChanged:
                return .none
            case .started, .configurationChanged:
                return isPresented ? .minimize : .none
            }

        case .alwaysExpanded:
            return isPresented ? .none : .present

        case .smart:
            let isExcluded = frontmostBundleIdentifier.map {
                configuration.excludedBundleIdentifiers.contains($0)
            }
            guard let isExcluded else {
                // Unknown frontmost app: keep the current state on an app
                // switch, but apply the mode when starting or reconfiguring.
                return trigger == .frontmostChanged ? .none : (isPresented ? .none : .present)
            }
            if isExcluded {
                return isPresented ? .minimize : .none
            }
            return isPresented ? .none : .present
        }
    }

    private func reloadConfiguration() {
        touchBarConfiguration = userDefaultsRepository.touchBarConfiguration
        showsMetricsBarOnTouchBar = userDefaultsRepository.showsMetricsBarOnTouchBar
    }

    private func applyCurrentDecision(trigger: Trigger) {
        guard showsMetricsBarOnTouchBar else {
            minimizeMetricsBar()
            removeTrayItem()
            return
        }
        if trayItem == nil {
            setupTrayItem()
        }
        switch Self.evaluate(
            configuration: touchBarConfiguration,
            isEnabled: showsMetricsBarOnTouchBar,
            isHardwareAvailable: true,
            frontmostBundleIdentifier: frontmostApplicationInfo?.bundleIdentifier,
            isPresented: isPresented,
            trigger: trigger
        ) {
        case .present:
            presentMetricsBar()
        case .minimize:
            minimizeMetricsBar()
        case .none:
            if trigger == .started {
                primeTrayItemIfNeeded()
            }
        }
    }

    /// The Control Strip only renders a tray item for a bar the system has seen
    /// presented, so a mode that starts collapsed primes it with an immediate
    /// present-and-collapse to make the anchor icon visible from launch.
    private func primeTrayItemIfNeeded() {
        guard let touchBar, let trayItem, !isPresented else { return }
        guard touchBarClient.presentSystemModal(touchBar, trayItem.identifier.rawValue) else { return }
        isPresented = true
        DispatchQueue.main.async { [weak self] in
            self?.minimizeMetricsBar()
        }
    }

    private func removeTrayItem() {
        guard let trayItem else { return }
        _ = touchBarClient.removeSystemTrayItem(trayItem)
        self.trayItem = nil
    }

    private func presentMetricsBar() {
        guard let touchBar, let trayItem, !isPresented else { return }
        isPresented = touchBarClient.presentSystemModal(touchBar, trayItem.identifier.rawValue)
        logService.notice(.touchBarSetup(step: "present", detail: "result=\(isPresented)"))
    }

    private func minimizeMetricsBar() {
        guard let touchBar, isPresented else { return }
        _ = touchBarClient.minimizeSystemModal(touchBar)
        isPresented = false
        logService.notice(.touchBarSetup(step: "minimize", detail: "done"))
    }

    // MARK: - Observation

    private func observe() async {
        let appStateClient = self.appStateClient
        let nsWorkspaceClient = self.nsWorkspaceClient
        await withTaskGroup { group in
            group.addImmediateTask { [weak self] in
                let stream = appStateClient.withLock(\.touchBarConfigurationChanges.stream)
                for await _ in stream {
                    self?.reloadConfiguration()
                    self?.applyCurrentDecision(trigger: .configurationChanged)
                }
            }
            group.addImmediateTask { [weak self] in
                let stream = nsWorkspaceClient.frontmostApplicationChanges().values
                for await info in stream {
                    guard let info else { continue }
                    self?.frontmostApplicationInfo = info
                    if info.bundleIdentifier != Self.ownBundleIdentifier {
                        self?.appStateClient.withLock { $0.lastExternalFrontmostApplication = info }
                    }
                    self?.applyCurrentDecision(trigger: .frontmostChanged)
                }
            }
        }
    }

    // MARK: - Touch Bar setup

    private func setupTrayItem() {
        guard let image = NSImage(systemSymbolName: "gauge.high", accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "gauge", accessibilityDescription: nil) else {
            logService.notice(.touchBarSetup(step: "tray", detail: "no symbol image"))
            return
        }
        let item = NSCustomTouchBarItem(identifier: Self.trayItemIdentifier)
        let button = NSButton(image: image, target: self, action: #selector(trayItemTapped(_:)))
        button.isBordered = false
        item.view = button
        let added = touchBarClient.addSystemTrayItem(item)
        logService.notice(.touchBarSetup(step: "tray", detail: "added=\(added)"))
        guard added else { return }
        trayItem = item
    }

    private func setupTouchBar() {
        let touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [Self.metricsItemIdentifier, Self.collapseItemIdentifier]
        self.touchBar = touchBar
    }

    // MARK: - NSTouchBarDelegate

    public func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case Self.metricsItemIdentifier:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = Self.metricsContentViewProvider?(appDependencies) ?? NSView()
            return item
        case Self.collapseItemIdentifier:
            guard let image = NSImage(systemSymbolName: "minus", accessibilityDescription: nil) else { return nil }
            let item = NSCustomTouchBarItem(identifier: identifier)
            let button = NSButton(image: image, target: self, action: #selector(collapseButtonTapped(_:)))
            button.isBordered = false
            item.view = button
            return item
        default:
            return nil
        }
    }

    // MARK: - Actions

    @objc private func trayItemTapped(_ sender: Any?) {
        // Re-present unconditionally: the system may have minimized the bar on
        // its own, which our local isPresented flag would never learn about.
        guard let touchBar, let trayItem else { return }
        isPresented = touchBarClient.presentSystemModal(touchBar, trayItem.identifier.rawValue)
        logService.notice(.touchBarSetup(step: "present(tray)", detail: "result=\(isPresented)"))
    }

    @objc private func collapseButtonTapped(_ sender: Any?) {
        minimizeMetricsBar()
    }
}
