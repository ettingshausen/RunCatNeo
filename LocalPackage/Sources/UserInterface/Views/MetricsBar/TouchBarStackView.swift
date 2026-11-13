/*
 TouchBarStackView.swift
 UserInterface

 Created by ettingshausen on 2026/11/13.
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

/// One fixed-width Touch Bar slot whose members rotate like an iOS widget
/// stack. The slot is as wide as its widest member so switching never shifts
/// its neighbours, and the transition rolls bottom to top: the outgoing member
/// slides up out of the clip while the next one slides in from below.
final class TouchBarStackView: NSView {
    private static let animationDuration: TimeInterval = 0.3

    private let bands: [NSView]
    private let slotWidth: CGFloat
    private let bandHeight: CGFloat
    private var isAnimating = false
    private(set) var activeIndex = 0

    var memberCount: Int { bands.count }

    init(members: [NSView], width: CGFloat, height: CGFloat) {
        slotWidth = max(ceil(width), 1)
        bandHeight = height
        bands = members.map { member in
            let band = NSView(frame: NSRect(x: 0, y: 0, width: max(ceil(width), 1), height: height))
            band.wantsLayer = true
            member.layoutSubtreeIfNeeded()
            let fitting = member.fittingSize
            member.frame = NSRect(
                x: 0,
                y: floor((height - fitting.height) / 2),
                width: min(ceil(fitting.width), max(ceil(width), 1)),
                height: max(fitting.height, 1)
            )
            member.translatesAutoresizingMaskIntoConstraints = true
            band.addSubview(member)
            return band
        }
        super.init(frame: NSRect(x: 0, y: 0, width: slotWidth, height: height))
        wantsLayer = true
        layer?.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: slotWidth),
            heightAnchor.constraint(equalToConstant: height),
        ])
        for band in bands {
            addSubview(band)
        }
        placeBands()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows a member immediately. Used when the bar is rebuilt so a stack
    /// picks up where it left off instead of restarting at its first item.
    func setActive(index: Int) {
        guard !bands.isEmpty else { return }
        activeIndex = index % bands.count
        placeBands()
    }

    /// Rolls to the next member. The completion handler puts the incoming
    /// band at the exact on-screen position it already reached, so the reset
    /// never flashes.
    func advance() {
        guard memberCount > 1, !isAnimating else { return }
        isAnimating = true
        let outgoing = bands[activeIndex]
        let incoming = bands[(activeIndex + 1) % bands.count]
        incoming.isHidden = false
        let outgoingTarget = NSRect(x: 0, y: bandHeight, width: slotWidth, height: bandHeight)
        let incomingTarget = NSRect(x: 0, y: 0, width: slotWidth, height: bandHeight)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            outgoing.animator().frame = outgoingTarget
            incoming.animator().frame = incomingTarget
        } completionHandler: { [weak self] in
            guard let self else { return }
            // AppKit runs this on the main run loop but types it as a plain
            // Sendable closure, so hop back explicitly.
            MainActor.assumeIsolated {
                self.isAnimating = false
                self.activeIndex = (self.activeIndex + 1) % self.bands.count
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.placeBands()
                CATransaction.commit()
            }
        }
    }

    /// Keeps the active member on screen, the next member hidden just below
    /// the clip (ready to roll in) and every other member hidden above it.
    private func placeBands() {
        guard !bands.isEmpty else { return }
        let next = (activeIndex + 1) % bands.count
        for (index, band) in bands.enumerated() {
            band.frame = NSRect(x: 0, y: 0, width: slotWidth, height: bandHeight)
            if index == activeIndex {
                band.isHidden = false
            } else if memberCount > 1 && index == next {
                band.isHidden = false
                band.frame.origin.y = -bandHeight
            } else {
                band.isHidden = true
                band.frame.origin.y = bandHeight * 2
            }
        }
    }
}
