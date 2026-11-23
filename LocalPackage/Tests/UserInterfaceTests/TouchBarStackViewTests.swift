/*
 TouchBarStackViewTests.swift
 UserInterfaceTests

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
import Testing
@testable import UserInterface

@MainActor
struct TouchBarStackViewTests {
    /// Reproduces the clipped "100%" keyboard battery cell: the slot is built
    /// while the member reads "94%" and the live value later widens to
    /// "100%". After the update path (stringValue + sizeToFit) and
    /// refreshMemberWidths, the slot must be wide enough that the label's
    /// trailing glyph is not cut.
    @Test
    func slotGrowsWhenMemberValueWidens() {
        let field = LabelTextField(labelWithString: "94%")
        field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        field.lineBreakMode = .byClipping

        let cell = NSStackView()
        cell.orientation = .horizontal
        cell.alignment = .centerY
        cell.spacing = 3
        cell.addArrangedSubview(field)

        let stack = TouchBarStackView(members: [cell], width: 40, height: 30)
        let fieldWidthBefore = ceil(field.intrinsicContentSize.width)

        // The live-value update path from TouchBarMetricsContainerView.
        field.stringValue = "100%"
        field.invalidateIntrinsicContentSize()
        field.sizeToFit()
        stack.invalidateIntrinsicContentSize()
        stack.needsLayout = true
        stack.layoutSubtreeIfNeeded()
        let grew = stack.refreshMemberWidths()
        stack.layoutSubtreeIfNeeded()

        #expect(grew || stack.frame.width >= fieldWidthBefore)
        // The label's full text width must fit inside the member frame and
        // the slot, otherwise the trailing "%" is clipped. (The field's own
        // frame may overhang by the cell's margins — sizeToFit sizes to
        // cellSize, NSStackView lays out by intrinsicContentSize — but the
        // glyphs start inside those margins.)
        let member = stack.subviews[0].subviews.first!
        #expect(member.frame.width >= ceil(field.intrinsicContentSize.width) - 0.5)
        #expect(stack.frame.width >= member.frame.width - 0.5)
    }
}
