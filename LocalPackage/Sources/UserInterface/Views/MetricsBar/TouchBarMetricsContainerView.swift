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
import Model
import SwiftUI

/// Hosts the metrics bar content for a Touch Bar item and reports the content's
/// ideal width as its intrinsic size. The Touch Bar sizes custom items from the
/// view's intrinsic size, and a bare `NSHostingView` does not update it when the
/// SwiftUI content grows, which squeezes the labels into "…".
public final class TouchBarMetricsContainerView: NSView {
    private let hostingView: NSHostingView<TouchBarMetricsBarView>
    private var lastFittingWidth: CGFloat = -1

    public init(_ appDependencies: AppDependencies) {
        hostingView = NSHostingView(rootView: TouchBarMetricsBarView(appDependencies))
        super.init(frame: NSRect(x: 0, y: 0, width: 1, height: Self.height))
        hostingView.autoresizingMask = [.width, .height]
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        // Labels must never be squeezed into "…": refuse any horizontal
        // compression of the hosted SwiftUI content.
        hostingView.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static let height: CGFloat = 28

    public override var intrinsicContentSize: NSSize {
        NSSize(width: max(hostingView.fittingSize.width, 1), height: Self.height)
    }
    public override func layout() {
        super.layout()
        let fittingWidth = hostingView.fittingSize.width
        guard abs(fittingWidth - lastFittingWidth) > 0.5 else { return }
        lastFittingWidth = fittingWidth
        invalidateIntrinsicContentSize()
        // The Touch Bar reads the item's width once at insertion and never
        // re-queries the intrinsic size, so keep the frame in sync ourselves.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.setFrameSize(NSSize(
                width: max(fittingWidth, 1),
                height: Self.height
            ))
        }
    }

    /// Applies the current content width immediately, for the moment a bar is
    /// presented before any content change has triggered a layout pass.
    public func syncIdealSize() {
        setFrameSize(NSSize(width: max(hostingView.fittingSize.width, 1), height: Self.height))
    }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard superview != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.syncIdealSize()
        }
    }
}
