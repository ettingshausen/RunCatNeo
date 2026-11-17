import Foundation
import Testing

@testable import DataSource

struct TouchBarIndicatorBrightnessTests {
    @Test
    func clamp_bounds_the_offered_range() {
        #expect(TouchBarIndicatorBrightness.clamp(1.0) == 1.0)
        #expect(TouchBarIndicatorBrightness.clamp(0.3) == 0.3)
        #expect(TouchBarIndicatorBrightness.clamp(0.62) == 0.62)
        #expect(TouchBarIndicatorBrightness.clamp(0.0) == TouchBarIndicatorBrightness.minimum)
        #expect(TouchBarIndicatorBrightness.clamp(-1.0) == TouchBarIndicatorBrightness.minimum)
        #expect(TouchBarIndicatorBrightness.clamp(2.0) == TouchBarIndicatorBrightness.maximum)
    }

    @Test
    func clamp_treats_non_finite_values_as_the_default() {
        #expect(TouchBarIndicatorBrightness.clamp(.nan) == TouchBarIndicatorBrightness.default)
        #expect(TouchBarIndicatorBrightness.clamp(.infinity) == TouchBarIndicatorBrightness.maximum)
    }

    @Test
    func default_is_full_brightness_with_a_stable_key() {
        #expect(TouchBarIndicatorBrightness.default == 1.0)
        #expect(TouchBarIndicatorBrightness.defaultsKey == "TouchBarIndicatorBrightness")
        #expect(TouchBarIndicatorBrightness.minimum < TouchBarIndicatorBrightness.maximum)
    }
}
