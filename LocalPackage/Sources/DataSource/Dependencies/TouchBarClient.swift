/*
 TouchBarClient.swift
 DataSource

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
import IOKit

public struct TouchBarClient: DependencyClient {
    public var hasHardware: @Sendable () -> Bool
    public var arePrivateSelectorsAvailable: @Sendable () -> Bool
    public var addSystemTrayItem: @Sendable (NSTouchBarItem) -> Bool
    public var removeSystemTrayItem: @Sendable (NSTouchBarItem) -> Bool
    public var presentSystemModal: @Sendable (NSTouchBar, String) -> Bool
    public var minimizeSystemModal: @Sendable (NSTouchBar) -> Bool
    public var dismissSystemModal: @Sendable (NSTouchBar) -> Bool

    public static let liveValue = Self(
        hasHardware: { TouchBarHardwareProbe.hasHardware },
        arePrivateSelectorsAvailable: {
            let touchBarClass: AnyObject = NSTouchBar.self
            let touchBarItemClass: AnyObject = NSTouchBarItem.self
            return TouchBarPrivateSelector.allSatisfy({ selector, receiver in
                (receiver == .touchBar ? touchBarClass : touchBarItemClass).responds(to: selector)
            })
        },
        addSystemTrayItem: { item in
            performClassMethod(NSTouchBarItem.self, TouchBarPrivateSelector.addSystemTrayItem, arguments: [item])
        },
        removeSystemTrayItem: { item in
            performClassMethod(NSTouchBarItem.self, TouchBarPrivateSelector.removeSystemTrayItem, arguments: [item])
        },
        presentSystemModal: { touchBar, systemTrayItemIdentifier in
            performClassMethod(
                NSTouchBar.self,
                TouchBarPrivateSelector.presentSystemModal,
                arguments: [touchBar, systemTrayItemIdentifier]
            )
        },
        minimizeSystemModal: { touchBar in
            performClassMethod(NSTouchBar.self, TouchBarPrivateSelector.minimizeSystemModal, arguments: [touchBar])
        },
        dismissSystemModal: { touchBar in
            performClassMethod(NSTouchBar.self, TouchBarPrivateSelector.dismissSystemModal, arguments: [touchBar])
        }
    )

    public static let testValue = Self(
        hasHardware: { false },
        arePrivateSelectorsAvailable: { false },
        addSystemTrayItem: { _ in false },
        removeSystemTrayItem: { _ in false },
        presentSystemModal: { _, _ in false },
        minimizeSystemModal: { _ in false },
        dismissSystemModal: { _ in false }
    )
}

/// Private `DFRFoundation`-backed class methods that keep a Touch Bar item
/// alive outside the frontmost app. Verified to exist on macOS 26/27; each
/// call site checks availability before invoking.
private enum TouchBarPrivateSelector {
    enum Receiver {
        case touchBar
        case touchBarItem
    }

    static let addSystemTrayItem = NSSelectorFromString("addSystemTrayItem:")
    static let removeSystemTrayItem = NSSelectorFromString("removeSystemTrayItem:")
    static let presentSystemModal = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")
    static let minimizeSystemModal = NSSelectorFromString("minimizeSystemModalTouchBar:")
    static let dismissSystemModal = NSSelectorFromString("dismissSystemModalTouchBar:")

    static func allSatisfy(_ predicate: (Selector, Receiver) -> Bool) -> Bool {
        predicate(addSystemTrayItem, .touchBarItem)
            && predicate(removeSystemTrayItem, .touchBarItem)
            && predicate(presentSystemModal, .touchBar)
            && predicate(minimizeSystemModal, .touchBar)
            && predicate(dismissSystemModal, .touchBar)
    }
}

/// Invokes a class method by selector on the class object. All target
/// selectors take object arguments only, so `perform(_:with:with:)` suffices.
private func performClassMethod(_ cls: AnyObject, _ selector: Selector, arguments: [Any]) -> Bool {
    guard cls.responds(to: selector) else { return false }
    switch arguments.count {
    case 1: _ = cls.perform(selector, with: arguments[0])
    case 2: _ = cls.perform(selector, with: arguments[0], with: arguments[1])
    default: return false
    }
    return true
}

/// Touch Bar (DFR display) hardware probe. Intel-era models expose an
/// `AppleDFR` IOService class; Apple Silicon models expose the DFR display
/// under device-tree names (`lcddfr`, `dispdfr`) that must be name-matched.
private enum TouchBarHardwareProbe {
    static var hasHardware: Bool {
        if serviceExists(matching: IOServiceMatching("AppleDFR")) { return true }
        if serviceExists(matching: IOServiceNameMatching("lcddfr")) { return true }
        if serviceExists(matching: IOServiceNameMatching("dispdfr")) { return true }
        return false
    }

    private static func serviceExists(matching dictionary: CFMutableDictionary?) -> Bool {
        guard let dictionary else { return false }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, dictionary)
        guard service != IO_OBJECT_NULL else { return false }
        IOObjectRelease(service)
        return true
    }
}
