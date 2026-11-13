import AllocatedUnfairLock
import Foundation
import Testing

@testable import DataSource
@testable import Model

@MainActor
struct StockEditorTests {
    private let fixture = """
    var hq_str_sh600519="贵州茅台,1395.130,1402.300,1410.270,1411.000,1388.110,1410.270,1410.430,3237294,4536814518.000,1655,1410.270,100,1410.220,400,1410.210,400,1410.190,100,1410.000,200,1410.430,100,1410.450,100,1410.460,500,1410.500,100,1410.550,2026-11-12,15:34:59,00,D|2000|2820540.00";
    """

    private struct Outcome {
        var addedStocks: [Stock] = []
        var errors: [RCNError] = []
        var fetchCount = 0
    }

    private func makeEditor(
        symbol: String = "",
        abbreviation: String = "",
        existingStocks: [Stock] = [],
        fetch: (@Sendable ([String]) throws -> String)? = nil
    ) -> (StockEditor, () -> Outcome) {
        let outcome = AllocatedUnfairLock<Outcome>(initialState: .init())
        let editor = StockEditor(
            .testDependencies(
                stockClient: testDependency(of: StockClient.self) {
                    if let fetch {
                        $0.fetch = { symbols in
                            outcome.withLock { $0.fetchCount += 1 }
                            return try fetch(symbols)
                        }
                    }
                }
            ),
            existingStocks: existingStocks,
            symbol: symbol,
            abbreviation: abbreviation,
            action: { action in
                switch action {
                case let .stockAdded(stock):
                    outcome.withLock { $0.addedStocks.append(stock) }
                case let .errorOccurred(error):
                    outcome.withLock { $0.errors.append(error) }
                default:
                    break
                }
            }
        )
        return (editor, { outcome.withLock(\.self) })
    }

    @Test
    func add_rejects_unrecognizable_input_before_touching_the_network() async {
        let (editor, outcome) = makeEditor(symbol: "###")
        await editor.send(.addButtonTapped)
        #expect(outcome().errors == [.stock(.invalidSymbol)])
        #expect(outcome().fetchCount == 0)
        #expect(outcome().addedStocks.isEmpty)
    }

    @Test
    func add_validates_the_code_with_a_live_quote_and_fills_the_name_as_abbreviation() async throws {
        let (editor, outcome) = makeEditor(symbol: "Sh600519") { _ in fixture }
        await editor.send(.addButtonTapped)
        let result = outcome()
        #expect(result.errors.isEmpty)
        #expect(result.addedStocks.count == 1)
        let stock = try #require(result.addedStocks.first)
        #expect(stock.symbol == "sh600519")
        #expect(stock.abbreviation == "贵州茅台")
    }

    @Test
    func add_keeps_a_custom_abbreviation() async {
        let (editor, outcome) = makeEditor(symbol: "sh600519", abbreviation: "茅台") { _ in fixture }
        await editor.send(.addButtonTapped)
        #expect(outcome().addedStocks.first?.abbreviation == "茅台")
    }

    @Test
    func add_rejects_duplicates_without_touching_the_network() async {
        let existing = [Stock(id: UUID(), symbol: "sh600519", abbreviation: "茅台")]
        let (editor, outcome) = makeEditor(symbol: "sh600519", existingStocks: existing)
        await editor.send(.addButtonTapped)
        #expect(outcome().errors == [.stock(.duplicateSymbol)])
        #expect(outcome().fetchCount == 0)
    }

    @Test
    func add_reports_an_unlisted_code_as_invalid_instead_of_a_network_failure() async {
        // Sina answers an unlisted code with an empty payload; that is a bad
        // code, not a failed request.
        let (editor, outcome) = makeEditor(symbol: "gb_msft") { _ in
            """
            var hq_str_gb_msft="";
            """
        }
        await editor.send(.addButtonTapped)
        #expect(outcome().errors == [.stock(.invalidSymbol)])
        #expect(outcome().fetchCount == 1)
        #expect(outcome().addedStocks.isEmpty)
    }

    @Test
    func add_reports_a_fetch_failure() async {
        let (editor, outcome) = makeEditor(symbol: "gb_msft") { _ in
            throw URLError(.timedOut)
        }
        await editor.send(.addButtonTapped)
        #expect(outcome().errors == [.stock(.fetchFailed)])
        #expect(outcome().addedStocks.isEmpty)
    }

    @Test
    func bare_codes_are_normalized_into_sina_codes() {
        #expect(StockEditor.normalizedSymbol("300253") == "sz300253")
        #expect(StockEditor.normalizedSymbol("600519") == "sh600519")
        #expect(StockEditor.normalizedSymbol("688981") == "sh688981")
        #expect(StockEditor.normalizedSymbol("000001") == "sz000001")
        #expect(StockEditor.normalizedSymbol("430047") == "bj430047")
        #expect(StockEditor.normalizedSymbol("0700") == "rt_hk00700")
        #expect(StockEditor.normalizedSymbol("700") == "rt_hk00700")
        #expect(StockEditor.normalizedSymbol("AAPL") == "gb_aapl")
        #expect(StockEditor.normalizedSymbol("sh600519") == "sh600519")
        #expect(StockEditor.normalizedSymbol("rt_hk00700") == "rt_hk00700")
        #expect(StockEditor.normalizedSymbol("gb_brk.b") == "gb_brk.b")
        #expect(StockEditor.normalizedSymbol("999999") == nil)
        #expect(StockEditor.normalizedSymbol("") == nil)
    }

    @Test
    func add_normalizes_bare_codes() async {
        let (editor, outcome) = makeEditor(symbol: "300253") { _ in
            "var hq_str_sz300253=\"卫宁健康,10.560,10.660,11.180,11.240,10.560,11.180,11.180,80632666,897090000.000,2637,11.180,1200,11.170,600,11.160,500,11.150,300,11.140,200,11.190,400,11.200,300,11.210,700,11.220,500,11.230,2026-11-13,15:00:01,00\";"
        }
        await editor.send(.addButtonTapped)
        #expect(outcome().errors.isEmpty)
        #expect(outcome().addedStocks.first?.symbol == "sz300253")
        #expect(outcome().addedStocks.first?.abbreviation == "卫宁健康")
    }

    @Test
    func symbol_validation_accepts_the_three_markets() {
        #expect(StockEditor.isValidSymbol("sh600519"))
        #expect(StockEditor.isValidSymbol("sz000001"))
        #expect(StockEditor.isValidSymbol("rt_hk00700"))
        #expect(StockEditor.isValidSymbol("gb_aapl"))
        #expect(StockEditor.isValidSymbol("gb_brk.b"))
        #expect(!StockEditor.isValidSymbol("600519"))
        #expect(!StockEditor.isValidSymbol("sh60051"))
        #expect(!StockEditor.isValidSymbol("rt_hkabc"))
        #expect(!StockEditor.isValidSymbol("hk00700"))
    }
}
