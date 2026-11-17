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
    static let stockBrightnessDefaultsKey = "TouchBarStockIndicatorBrightness"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            pixelShiftDefaultsKey: true,
            stockBrightnessDefaultsKey: 1.0,
            TouchBarIndicatorBrightness.defaultsKey: TouchBarIndicatorBrightness.default,
        ])
    }

    static var stockBrightness: Double {
        min(max(UserDefaults.standard.double(forKey: stockBrightnessDefaultsKey), 0.7), 1.5)
    }

    /// The neutral-content luminance factor set from the bar's brightness
    /// page. Stock colors do not use it.
    static var indicatorBrightness: Double {
        TouchBarIndicatorBrightness.clamp(
            UserDefaults.standard.double(forKey: TouchBarIndicatorBrightness.defaultsKey)
        )
    }

    static func setIndicatorBrightness(_ value: Double) {
        UserDefaults.standard.set(
            TouchBarIndicatorBrightness.clamp(value),
            forKey: TouchBarIndicatorBrightness.defaultsKey
        )
    }

    /// Brightens or dims stock colors without changing their up/down hue.
    static func stockColor(for direction: StockDirection) -> NSColor {
        let base = color(for: direction)
        let brightness = stockBrightness
        let components = base.usingColorSpace(.deviceRGB) ?? base
        func adjusted(_ component: CGFloat) -> CGFloat {
            min(component * brightness, 1)
        }
        return NSColor(
            srgbRed: adjusted(components.redComponent),
            green: adjusted(components.greenComponent),
            blue: adjusted(components.blueComponent),
            alpha: components.alphaComponent
        )
    }

    static let background = NSColor.black

    /// Neutral content follows the bar's brightness setting; scaled in place
    /// so the values read as one consistent dim level.
    private static func dimmed(_ color: NSColor, by factor: Double) -> NSColor {
        let components = color.usingColorSpace(.deviceRGB) ?? color
        let scale = CGFloat(factor)
        return NSColor(
            srgbRed: components.redComponent * scale,
            green: components.greenComponent * scale,
            blue: components.blueComponent * scale,
            alpha: components.alphaComponent
        )
    }

    /// Fixed symbols and separators should be dimmer than live values.
    static var staticIcon: NSColor {
        dimmed(NSColor(srgbRed: 0.49, green: 0.49, blue: 0.49, alpha: 1), by: indicatorBrightness)
    }

    static var separator: NSColor {
        dimmed(NSColor(srgbRed: 0.20, green: 0.20, blue: 0.20, alpha: 1), by: indicatorBrightness)
    }

    static var dynamicValue: NSColor {
        dimmed(NSColor(srgbRed: 0.76, green: 0.76, blue: 0.76, alpha: 1), by: indicatorBrightness)
    }

    /// The brightness page's own controls must stay readable at any setting.
    static let controlTrack = NSColor(srgbRed: 0.30, green: 0.30, blue: 0.30, alpha: 1)
    static let controlFill = NSColor(srgbRed: 0.85, green: 0.85, blue: 0.85, alpha: 1)
    /// The rounded card the brightness page sits on, like the system's
    /// brightness panel (lighter than the black bar behind it).
    static let panelCard = NSColor(srgbRed: 0.17, green: 0.17, blue: 0.18, alpha: 1)

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
