/*
 TouchBarRunnerView.swift
 UserInterface

 Created by ettingshausen on 2026/11/14.
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

/// Hosts the runner animation inside the Touch Bar metrics bar. The frames
/// come from the same CAKeyframeAnimation machinery as the menu bar
/// (`RunnerLayer`), scaled down from the menu bar's 18pt line height.
final class TouchBarRunnerView: NSView {
    static let runnerHeight: CGFloat = 16
    /// `RunnerLayer` pins its content 2pt above the bottom, so the host is
    /// 4pt taller to keep the runner vertically centered in the bar.
    static let hostHeight: CGFloat = runnerHeight + 4
    private static let menuBarLineHeight: CGFloat = 18

    private let runnerLayer = RunnerLayer(gap: 0)
    private var runnerWidth: CGFloat = 0

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: Self.hostHeight))
        wantsLayer = true
        layer?.addSublayer(runnerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: runnerWidth, height: Self.hostHeight)
    }

    /// The store's frames are normalized to 18pt for the menu bar; the Touch
    /// Bar shows them at 16pt, so copies are rescaled instead of mutating the
    /// shared images. The white tint matches the bar's other cells.
    func set(frames: [NSImage], isTemplate: Bool) {
        let scale = Self.runnerHeight / Self.menuBarLineHeight
        let scaled = frames.map { image -> NSImage in
            let copy = image.copy() as! NSImage
            copy.size = NSSize(width: image.size.width * scale, height: Self.runnerHeight)
            return copy
        }
        runnerWidth = scaled.first?.size.width ?? 0
        invalidateIntrinsicContentSize()
        runnerLayer.setFrames(scaled, isTemplate)
        runnerLayer.setColor(NSColor.white.cgColor, isTemplate)
    }

    func setSpeed(_ speed: Float) {
        runnerLayer.setSpeed(speed)
    }
}
