import Foundation
import Testing

@testable import DataSource

struct IntExtensionTests {
    @Test
    func token_count_keeps_the_menubar_abbreviations_by_default() {
        #expect(912.formattedTokenCount == "912")
        #expect(1_200.formattedTokenCount == "1.2K")
        #expect(88_400_000.formattedTokenCount == "88.4M")
        #expect(197_300_000.formattedTokenCount == "197M")
        #expect(1_230_000_000.formattedTokenCount == "1.2B")
        #expect((-5).formattedTokenCount == "0")
    }

    @Test
    func token_count_switches_to_oku_above_one_hundred_million_for_chinese_units() {
        #expect(99_000_000.formattedTokenCount(usesChineseUnits: true) == "99M")
        #expect(100_000_000.formattedTokenCount(usesChineseUnits: true) == "1亿")
        #expect(197_300_000.formattedTokenCount(usesChineseUnits: true) == "1.97亿")
        #expect(1_500_000_000.formattedTokenCount(usesChineseUnits: true) == "15亿")
        #expect(500_000_000.formattedTokenCount(usesChineseUnits: true) == "5亿")
    }

    @Test
    func token_count_below_one_hundred_million_is_unchanged_by_the_unit_preference() {
        for value in [0, 912, 1_200, 88_400_000, 99_000_000] {
            #expect(value.formattedTokenCount == value.formattedTokenCount(usesChineseUnits: true))
        }
    }
}
