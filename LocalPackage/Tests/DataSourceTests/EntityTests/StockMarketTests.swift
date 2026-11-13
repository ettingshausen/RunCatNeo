import Foundation
import Testing

@testable import DataSource

struct StockMarketTests {
    private func date(
        _ market: StockMarket,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        month: Int = 11,
        year: Int = 2026
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = market.timeZone
        return calendar.date(from: components)!
    }

    @Test
    func symbols_map_to_their_markets() {
        #expect(StockMarket(symbol: "sh600519") == .china)
        #expect(StockMarket(symbol: "sz000001") == .china)
        #expect(StockMarket(symbol: "bj430047") == .china)
        #expect(StockMarket(symbol: "rt_hk00700") == .hongKong)
        #expect(StockMarket(symbol: "gb_aapl") == .unitedStates)
        #expect(StockMarket(symbol: "unknown") == nil)
    }

    @Test
    func china_skips_the_lunch_break_and_the_closed_hours() {
        // 2026-11-18 is a Wednesday.
        #expect(!StockMarket.china.isOpen(at: date(.china, 18, 9, 29)))
        #expect(StockMarket.china.isOpen(at: date(.china, 18, 9, 30)))
        #expect(StockMarket.china.isOpen(at: date(.china, 18, 11, 29)))
        #expect(!StockMarket.china.isOpen(at: date(.china, 18, 11, 30)))
        #expect(!StockMarket.china.isOpen(at: date(.china, 18, 12, 59)))
        #expect(StockMarket.china.isOpen(at: date(.china, 18, 13, 0)))
        #expect(StockMarket.china.isOpen(at: date(.china, 18, 14, 59)))
        #expect(!StockMarket.china.isOpen(at: date(.china, 18, 15, 0)))
    }

    @Test
    func hong_kong_uses_its_own_session_boundaries() {
        #expect(!StockMarket.hongKong.isOpen(at: date(.hongKong, 18, 9, 29)))
        #expect(StockMarket.hongKong.isOpen(at: date(.hongKong, 18, 9, 30)))
        #expect(StockMarket.hongKong.isOpen(at: date(.hongKong, 18, 11, 59)))
        #expect(!StockMarket.hongKong.isOpen(at: date(.hongKong, 18, 12, 0)))
        #expect(StockMarket.hongKong.isOpen(at: date(.hongKong, 18, 13, 0)))
        #expect(StockMarket.hongKong.isOpen(at: date(.hongKong, 18, 15, 59)))
        #expect(!StockMarket.hongKong.isOpen(at: date(.hongKong, 18, 16, 0)))
    }

    @Test
    func united_states_trades_in_new_york_time() {
        #expect(!StockMarket.unitedStates.isOpen(at: date(.unitedStates, 18, 9, 29)))
        #expect(StockMarket.unitedStates.isOpen(at: date(.unitedStates, 18, 9, 30)))
        #expect(StockMarket.unitedStates.isOpen(at: date(.unitedStates, 18, 15, 59)))
        #expect(!StockMarket.unitedStates.isOpen(at: date(.unitedStates, 18, 16, 0)))
    }

    @Test
    func weekends_are_never_open() {
        // 2026-11-21 and 2026-11-22 are Saturday and Sunday.
        for market in StockMarket.allCases {
            #expect(!market.isTradingDay(at: date(market, 21, 10, 0)))
            #expect(!market.isTradingDay(at: date(market, 22, 10, 0)))
            #expect(!market.isOpen(at: date(market, 21, 10, 0)))
            #expect(!market.isOpen(at: date(market, 22, 10, 0)))
        }
    }

    @Test
    func probing_waits_for_the_opening_quotes() {
        #expect(!StockMarket.china.canProbe(at: date(.china, 18, 9, 31)))
        #expect(StockMarket.china.canProbe(at: date(.china, 18, 9, 32)))
        #expect(!StockMarket.hongKong.canProbe(at: date(.hongKong, 18, 9, 31)))
        #expect(StockMarket.hongKong.canProbe(at: date(.hongKong, 18, 9, 32)))
        #expect(!StockMarket.unitedStates.canProbe(at: date(.unitedStates, 18, 9, 34)))
        #expect(StockMarket.unitedStates.canProbe(at: date(.unitedStates, 18, 9, 35)))
        #expect(!StockMarket.china.canProbe(at: date(.china, 21, 10, 0)))
    }

    @Test
    func local_date_uses_the_market_timezone() {
        #expect(StockMarket.china.localDateKey(date(.china, 14, 0, 30)) == "2026-11-14")
        // 01:00 in Beijing is still the previous afternoon in New York.
        #expect(StockMarket.unitedStates.localDateKey(date(.unitedStates, 13, 12, 0)) == "2026-11-13")
    }

    @Test
    func each_market_probes_a_broad_index() {
        #expect(StockMarket.china.probeSymbol == "sh000001")
        #expect(StockMarket.hongKong.probeSymbol == "rt_hkHSI")
        #expect(StockMarket.unitedStates.probeSymbol == "gb_dji")
    }
}
