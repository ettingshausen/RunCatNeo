import Foundation
import Testing

@testable import DataSource

struct TouchBarStockBrightnessTests {
    @Test
    func clamp_bounds_the_offered_range() {
        #expect(TouchBarStockBrightness.clamp(1.0) == 1.0)
        #expect(TouchBarStockBrightness.clamp(0.7) == 0.7)
        #expect(TouchBarStockBrightness.clamp(1.5) == 1.5)
        #expect(TouchBarStockBrightness.clamp(0.2) == TouchBarStockBrightness.minimum)
        #expect(TouchBarStockBrightness.clamp(2.0) == TouchBarStockBrightness.maximum)
        #expect(TouchBarStockBrightness.clamp(.nan) == TouchBarStockBrightness.default)
    }

    @Test
    func rounded_snaps_to_the_step_the_settings_slider_uses() {
        #expect(TouchBarStockBrightness.rounded(1.02) == 1.0)
        #expect(TouchBarStockBrightness.rounded(1.03) == 1.05)
        #expect(TouchBarStockBrightness.rounded(0.68) == 0.7)
        #expect(TouchBarStockBrightness.rounded(1.49) == 1.5)
    }

    @Test
    func range_matches_the_settings_slider() {
        #expect(TouchBarStockBrightness.minimum == 0.7)
        #expect(TouchBarStockBrightness.maximum == 1.5)
        #expect(TouchBarStockBrightness.step == 0.05)
        #expect(TouchBarStockBrightness.default == 1.0)
        #expect(TouchBarStockBrightness.defaultsKey == "TouchBarStockIndicatorBrightness")
    }
}
