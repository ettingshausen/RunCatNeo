/*
 TouchBarOLEDTheme.swift
 UserInterface

 Licensed under the Apache License, Version 2.0.
 */

import AppKit
import DataSource

/// Conservative colors for custom Touch Bar content. These colors reduce
/// unnecessary luminance from static decoration while keeping live values
/// legible. They cannot prevent or measure OLED wear.
enum TouchBarOLEDTheme {
    static let pixelShiftDefaultsKey = "TouchBarOLEDProtectionPixelShiftEnabled"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [pixelShiftDefaultsKey: true])
    }

    static let background = NSColor.black

    /// Fixed symbols and separators should be dimmer than live values.
    static let staticIcon = NSColor(srgbRed: 0.49, green: 0.49, blue: 0.49, alpha: 1)
    static let separator = NSColor(srgbRed: 0.20, green: 0.20, blue: 0.20, alpha: 1)
    static let dynamicValue = NSColor(srgbRed: 0.76, green: 0.76, blue: 0.76, alpha: 1)

    /// Preserve the app's mainland-China market convention: red is up,
    /// green is down. Saturation is moderated rather than changing meaning.
    static func color(for direction: StockDirection) -> NSColor {
        switch direction {
        case .up:
            NSColor(srgbRed: 0.78, green: 0.25, blue: 0.23, alpha: 1)
        case .down:
            NSColor(srgbRed: 0.0, green: 0.48, blue: 0.14, alpha: 1)
        case .flat:
            dynamicValue
        }
    }
}
