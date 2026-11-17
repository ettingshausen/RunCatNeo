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
        UserDefaults.standard.register(defaults: [
            pixelShiftDefaultsKey: true,
            TouchBarStockBrightness.defaultsKey: TouchBarStockBrightness.default,
        ])
    }

    static var stockBrightness: Double {
        TouchBarStockBrightness.clamp(
            UserDefaults.standard.double(forKey: TouchBarStockBrightness.defaultsKey)
        )
    }

    /// Used by the settings slider and the Touch Bar's brightness page; both
    /// write the same key, so they always agree.
    static func setStockBrightness(_ value: Double) {
        UserDefaults.standard.set(
            TouchBarStockBrightness.rounded(value),
            forKey: TouchBarStockBrightness.defaultsKey
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

    /// Fixed symbols and separators should be dimmer than live values.
    static let staticIcon = NSColor(srgbRed: 0.49, green: 0.49, blue: 0.49, alpha: 1)
    static let separator = NSColor(srgbRed: 0.20, green: 0.20, blue: 0.20, alpha: 1)
    static let dynamicValue = NSColor(srgbRed: 0.76, green: 0.76, blue: 0.76, alpha: 1)

    /// The brightness page's own controls must stay readable at any setting.
    static let controlTrack = NSColor(srgbRed: 0.30, green: 0.30, blue: 0.32, alpha: 1)
    static let controlFill = NSColor(srgbRed: 0.85, green: 0.85, blue: 0.85, alpha: 1)
    /// The slider drawn by `TouchBarBrightnessSlider`, matching the system
    /// brightness control: a hairline track, a system-blue fill and a large
    /// white rounded-square knob.
    static let sliderTrack = NSColor(srgbRed: 0.34, green: 0.34, blue: 0.36, alpha: 1)
    static let sliderFill = NSColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 1)
    static let sliderKnob = NSColor.white
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
