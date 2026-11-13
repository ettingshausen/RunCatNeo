import Foundation
import Testing

@testable import DataSource

struct StockConfigurationTests {
    private func decode(_ json: String) throws -> StockConfiguration {
        try JSONDecoder().decode(StockConfiguration.self, from: Data(json.utf8))
    }

    @Test
    func decode_without_interval_falls_back_to_thirty_seconds() throws {
        let configuration = try decode("""
        {"stocks":[{"id":"5C1C7A0E-6B71-4A46-9E0E-0B2C58A2E8F6","symbol":"sh600519","abbreviation":"茅台"}]}
        """)
        #expect(configuration.refreshInterval == 30)
        #expect(configuration.stocks.count == 1)
    }

    @Test
    func decode_keeps_a_known_interval() throws {
        let configuration = try decode("""
        {"stocks":[],"refreshInterval":5}
        """)
        #expect(configuration.refreshInterval == 5)
    }

    @Test
    func decode_normalizes_an_unknown_interval() throws {
        let configuration = try decode("""
        {"stocks":[],"refreshInterval":7}
        """)
        #expect(configuration.refreshInterval == 30)
    }

    @Test
    func encode_roundtrips_the_interval() throws {
        let configuration = StockConfiguration(stocks: [], refreshInterval: 15)
        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(StockConfiguration.self, from: data)
        #expect(decoded == configuration)
    }

    @Test
    func init_clamps_out_of_range_intervals() {
        #expect(StockConfiguration(stocks: [], refreshInterval: 0).refreshInterval == 30)
        #expect(StockConfiguration(stocks: [], refreshInterval: 60).refreshInterval == 30)
        #expect(StockConfiguration(stocks: [], refreshInterval: 10).refreshInterval == 10)
    }
}
