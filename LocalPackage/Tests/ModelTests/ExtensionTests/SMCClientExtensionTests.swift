import DataSource
import Foundation
import Testing

@testable import Model

struct SMCClientExtensionTests {
    @Test
    func numberValue_decodes_uint8_reading() throws {
        let reading = SMCClient.Reading(dataType: "ui8 ", dataBytes: [3])
        let value = try #require(reading.numberValue)
        #expect(value == 3.0)
    }

    @Test
    func numberValue_decodes_uint16_reading() throws {
        let reading = SMCClient.Reading(dataType: "ui16", dataBytes: [0x04, 0xB0])
        let value = try #require(reading.numberValue)
        #expect(value == 1200.0)
    }

    @Test
    func numberValue_decodes_uint32_reading() throws {
        let reading = SMCClient.Reading(dataType: "ui32", dataBytes: [0x00, 0x00, 0x06, 0xDC])
        let value = try #require(reading.numberValue)
        #expect(value == 1756.0)
    }

    @Test
    func numberValue_decodes_float_reading() throws {
        let dataBytes = withUnsafeBytes(of: Float(1234.5)) { Array($0) }
        let reading = SMCClient.Reading(dataType: "flt ", dataBytes: dataBytes)
        let value = try #require(reading.numberValue)
        #expect(value == 1234.5)
    }

    @Test
    func numberValue_decodes_fpe2_reading() throws {
        let reading = SMCClient.Reading(dataType: "fpe2", dataBytes: [0x12, 0xC0])
        let value = try #require(reading.numberValue)
        #expect(value == 1200.0)
    }

    @Test
    func numberValue_returns_nil_for_unknown_data_type() {
        let reading = SMCClient.Reading(dataType: "{foo", dataBytes: [0x00, 0x00, 0x00, 0x00])
        #expect(reading.numberValue == nil)
    }

    @Test
    func numberValue_returns_nil_when_bytes_are_short() {
        let reading = SMCClient.Reading(dataType: "flt ", dataBytes: [0x00, 0x00])
        #expect(reading.numberValue == nil)
    }
}
