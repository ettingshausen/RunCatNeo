import Foundation
import Testing

@testable import DataSource
@testable import Model

struct StockPollPlannerTests {
    /// 2026-11-18 is a Wednesday in every supported market.
    private func shanghai(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = day
        components.hour = hour
        components.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar.date(from: components)!
    }

    private func stock(_ symbol: String) -> Stock {
        Stock(id: UUID(), symbol: symbol, abbreviation: symbol)
    }

    @Test
    func an_open_market_polls_after_its_probe() {
        let now = shanghai(18, 10, 0)
        let plan = StockPollPlanner.plan(
            for: [stock("sh600519")],
            closedOn: [:],
            probedOn: [.china: StockMarket.china.localDateKey(now)],
            at: now
        )
        #expect(plan.symbols == ["sh600519"])
        #expect(plan.probeMarkets.isEmpty)
    }

    @Test
    func an_unprobed_market_is_probed_once_instead_of_polled() {
        let plan = StockPollPlanner.plan(
            for: [stock("sh600519"), stock("sz000001")],
            closedOn: [:],
            probedOn: [:],
            at: shanghai(18, 10, 0)
        )
        #expect(plan.symbols.isEmpty)
        #expect(plan.probeMarkets == [.china])
    }

    @Test
    func before_the_probe_window_nothing_is_requested() {
        let plan = StockPollPlanner.plan(
            for: [stock("sh600519")],
            closedOn: [:],
            probedOn: [:],
            at: shanghai(18, 9, 30)
        )
        #expect(plan.symbols.isEmpty)
        #expect(plan.probeMarkets.isEmpty)
    }

    @Test
    func a_holiday_is_skipped_for_the_rest_of_the_day() {
        let plan = StockPollPlanner.plan(
            for: [stock("sh600519")],
            closedOn: [.china: "2026-11-18"],
            probedOn: [:],
            at: shanghai(18, 10, 0)
        )
        #expect(plan.symbols.isEmpty)
        #expect(plan.probeMarkets.isEmpty)
    }

    @Test
    func the_lunch_break_and_the_closed_hours_are_skipped() {
        for minute in [12 * 60, 15 * 60 + 30, 8 * 60] {
            let now = shanghai(18, minute / 60, minute % 60)
            let plan = StockPollPlanner.plan(
                for: [stock("sh600519")],
                closedOn: [:],
                probedOn: [.china: StockMarket.china.localDateKey(now)],
                at: now
            )
            #expect(plan.symbols.isEmpty)
            #expect(plan.probeMarkets.isEmpty)
        }
    }

    @Test
    func weekends_are_skipped() {
        let plan = StockPollPlanner.plan(
            for: [stock("sh600519")],
            closedOn: [:],
            probedOn: [.china: "2026-11-21"],
            at: shanghai(21, 10, 0)
        )
        #expect(plan.symbols.isEmpty)
        #expect(plan.probeMarkets.isEmpty)
    }

    @Test
    func the_us_market_waits_for_its_own_opening_bell() {
        // 22:30 in Shanghai is 09:30 in New York (EST in November); the probe
        // needs five more minutes.
        let beforeProbe = StockPollPlanner.plan(
            for: [stock("gb_aapl")],
            closedOn: [:],
            probedOn: [:],
            at: shanghai(18, 22, 30)
        )
        #expect(beforeProbe.symbols.isEmpty)
        #expect(beforeProbe.probeMarkets.isEmpty)

        let atProbe = StockPollPlanner.plan(
            for: [stock("gb_aapl")],
            closedOn: [:],
            probedOn: [:],
            at: shanghai(18, 22, 35)
        )
        #expect(atProbe.symbols.isEmpty)
        #expect(atProbe.probeMarkets == [.unitedStates])
    }

    @Test
    func markets_are_filtered_independently() {
        let now = shanghai(18, 23, 0)
        let plan = StockPollPlanner.plan(
            for: [stock("sh600519"), stock("gb_aapl")],
            closedOn: [.china: "2026-11-18"],
            probedOn: [.unitedStates: StockMarket.unitedStates.localDateKey(now)],
            at: now
        )
        #expect(plan.symbols == ["gb_aapl"])
        #expect(plan.probeMarkets.isEmpty)
    }

    @Test
    func unknown_symbols_are_not_dropped() {
        let plan = StockPollPlanner.plan(
            for: [stock("weird")],
            closedOn: [:],
            probedOn: [:],
            at: shanghai(18, 12, 0)
        )
        #expect(plan.symbols == ["weird"])
        #expect(plan.probeMarkets.isEmpty)
    }

    @Test
    func a_probe_from_yesterday_marks_a_market_as_a_holiday() {
        #expect(!StockPollPlanner.isTradingDay(
            shanghai(17, 15, 0),
            of: .china,
            at: shanghai(18, 10, 0)
        ))
        #expect(StockPollPlanner.isTradingDay(
            shanghai(18, 10, 0),
            of: .china,
            at: shanghai(18, 10, 0)
        ))
    }
}
