/*
 TouchBarOLEDTheme.swift
 UserInterface

 Licensed under the Apache License, Version 2.0.
 */

import AppKit
import DataSource

/// Conservative colors for the custom Touch Bar content. This does not
/// control hardware brightness or guarantee prevention of OLED image retention.
enum TouchBarOLEDTheme {
    static let background = NSColor.black
    static let staticIcon = NSColor(calibratedWhite: 0.53, alpha: 1)
    static let dynamicValue = NSColor(calibratedWhite: 0.80, alpha: 1)

    static func color(for direction: StockDirection) -> NSColor {
        switch direction {
        case .up:
            NSColor(srgbRed: 0.78, green: 0.25, blue: 0.25, alpha: 1)
        case .down:
            NSColor(srgbRed: 0.0, green: 0.68, blue: 0.18, alpha: 1)
        case .flat:
            dynamicValue
        }
    }
}
