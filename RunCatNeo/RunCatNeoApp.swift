/*
 RunCatNeoApp.swift
 RunCatNeo

 Created by Takuto Nakamura on 2026/01/15.
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

import AppKit
import DataSource
import Model
import SwiftUI
import UserInterface

@main
struct RunCatNeoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(.showsMetricsBar) private var showsMetricsBar = false

    init() {
        TouchBarMetricsService.metricsContentViewProvider = { appDependencies in
            // The container reports the content's ideal width as its intrinsic
            // size; the Touch Bar sizes custom items from exactly that.
            TouchBarMetricsContainerView(appDependencies)
        }
    }

    #if DEBUG
    /// Temporary self-check: hosts the Touch Bar content in an offscreen window
    /// (so its `.task` lifecycle runs) and dumps the rendered bar to /tmp.
    private static func dumpTouchBarLayout() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            let view = TouchBarMetricsContainerView(AppDependencies.shared)
            let wrapper = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 90))
            let window = NSWindow(
                contentRect: NSRect(x: -3000, y: -3000, width: 800, height: 90),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = wrapper
            wrapper.addSubview(view)
            view.frame = NSRect(x: 0, y: 0, width: 800, height: 28)
            window.orderFront(nil)
            try? await Task.sleep(for: .seconds(3))
            print("[TBLayout] container frame=\(view.frame) intrinsic=\(view.intrinsicContentSize)")
            fflush(stdout)
            wrapper.layoutSubtreeIfNeeded()
            print("[TBLayout] container frame=\(view.frame) hostingFrame=\(view.subviews.first?.frame ?? .zero)")
            fflush(stdout)
            guard let rep = wrapper.bitmapImageRepForCachingDisplay(in: wrapper.bounds) else { return }
            wrapper.cacheDisplay(in: wrapper.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: "/tmp/tb-compact.png"))
            }
            window.close()
        }
    }
    #endif

    var body: some Scene {
        RunnerBarScene()
        MetricsBarScene(isInserted: $showsMetricsBar)
        SettingsWindowScene()
        OpenSourceLicenseWindowScene()
    }
}
