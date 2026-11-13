import Foundation
import Testing

@testable import DataSource
@testable import Model

struct StockQuoteParserTests {
    private let aShareLine = """
    var hq_str_sh600519="贵州茅台,1395.130,1402.300,1410.270,1411.000,1388.110,1410.270,1410.430,3237294,4536814518.000,1655,1410.270,100,1410.220,400,1410.210,400,1410.190,100,1410.000,200,1410.430,100,1410.450,100,1410.460,500,1410.500,100,1410.550,2026-11-12,15:34:59,00,D|2000|2820540.00";
    """

    private let hkLine = """
    var hq_str_rt_hk00700="TENCENT,腾讯控股,404.000,409.600,405.800,395.800,398.800,-10.800,-2.637,398.600,398.800,10372556992.478,25844607,14.494,0.000,652.399,375.200,2026/11/12,16:08:06,100|0,N|Y|Y,397.600|377.800|417.400,0|||0.000|0.000|0.000, |0,Y";
    """

    private let usLine = """
    var hq_str_gb_aapl="苹果,355.7758,0.12,2026-11-13 03:22:35,0.4158,357.8100,359.3684,355.0833,359.3684,242.8900,19114578,56132428,5170198677151,8.30,42.860000,0.00,0.00,0.00,0.00,14532182001,63,0.0000,0.00,0.00,,Nov 12 02:22PM EST,355.3600,0,1,2026,6827030078.0000,0.0000,0.0000,0.0000,0.0000,355.3600";
    """

    @Test
    func parse_a_share_computes_change_percent_from_prev_close() {
        let quotes = StockQuoteParser.parse(aShareLine)
        #expect(quotes.count == 1)
        let quote = quotes[0]
        #expect(quote.symbol == "sh600519")
        #expect(quote.name == "贵州茅台")
        #expect(quote.price == 1410.270)
        #expect(quote.prevClose == 1402.300)
        #expect(quote.changePercent! == (1410.270 - 1402.300) / 1402.300 * 100)
        #expect(quote.open == 1395.130)
        #expect(quote.high == 1411.000)
        #expect(quote.low == 1388.110)
    }

    @Test
    func parse_hk_share_takes_reported_change_fields() {
        let quotes = StockQuoteParser.parse(hkLine)
        #expect(quotes.count == 1)
        let quote = quotes[0]
        #expect(quote.symbol == "rt_hk00700")
        #expect(quote.name == "腾讯控股")
        #expect(quote.price == 398.800)
        #expect(quote.changePercent == -2.637)
        #expect(quote.changeAmount == -10.800)
        #expect(quote.prevClose == 409.600)
    }

    @Test
    func parse_us_share_takes_reported_change_fields() {
        let quotes = StockQuoteParser.parse(usLine)
        #expect(quotes.count == 1)
        let quote = quotes[0]
        #expect(quote.symbol == "gb_aapl")
        #expect(quote.name == "苹果")
        #expect(quote.price == 355.7758)
        #expect(quote.changePercent == 0.12)
        #expect(quote.prevClose == 355.3600)
    }

    @Test
    func parse_batch_skips_unknown_codes_and_keeps_order() {
        let text = [aShareLine, "var hq_str_gb_badcode=\"\";", hkLine].joined(separator: "\n")
        let quotes = StockQuoteParser.parse(text)
        #expect(quotes.map(\.symbol) == ["sh600519", "rt_hk00700"])
    }

    @Test
    func parse_ignores_non_sina_lines_and_empty_payloads() {
        let text = """
        random text without assignment
        var hq_str_gb_x="";
        """
        #expect(StockQuoteParser.parse(text).isEmpty)
    }

    @Test
    func parse_pre_open_share_keeps_yesterday_close_instead_of_a_hundred_percent_drop() {
        // Captured at 09:23 during the call auction: no live price yet.
        let line = """
        var hq_str_sz300253="卫宁健康,0.000,6.870,0.000,0.000,0.000,6.870,6.870,0,0.000,36700,6.870,21500,0.000,0,0.000,0,0.000,0,0.000,36700,6.870,0,0.000,0,0.000,0,0.000,0,0.000,2026-11-13,09:23:36,00";
        """
        let quotes = StockQuoteParser.parse(line)
        #expect(quotes.count == 1)
        let quote = quotes[0]
        #expect(quote.name == "卫宁健康")
        #expect(quote.price == 6.870)
        #expect(quote.changePercent == 0)
        #expect(quote.changeAmount == 0)
        #expect(quote.prevClose == 6.870)
        #expect(quote.open == nil)
        #expect(quote.high == nil)
        #expect(quote.low == nil)
    }

    @Test
    func parse_pre_open_hk_share_zeroes_the_reported_change() {
        let line = """
        var hq_str_rt_hk00700="TENCENT,腾讯控股,0.000,409.600,0.000,0.000,0.000,-10.800,-2.637,398.600,398.800,10372556992.478,25844607,14.494,0.000,652.399,375.200,2026/11/13,09:05:06,100|0,N|Y|Y,397.600|377.800|417.400,0|||0.000|0.000|0.000, |0,Y";
        """
        let quotes = StockQuoteParser.parse(line)
        #expect(quotes.count == 1)
        let quote = quotes[0]
        #expect(quote.price == 409.600)
        #expect(quote.changePercent == 0)
        #expect(quote.changeAmount == 0)
        #expect(quote.open == nil)
    }
}
