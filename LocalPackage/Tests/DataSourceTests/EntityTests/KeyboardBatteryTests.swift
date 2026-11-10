import Foundation
import Testing

@testable import DataSource

struct KeyboardBatteryTests {
    @Test
    func metricsBarConfiguration_decode_defaults_showsKeyboardBattery_to_false_for_legacy_payloads() throws {
        let json = """
        {"showsCPU":true,"showsMemory":false,"showsStorage":false,"showsBattery":false,"showsNetwork":true,"visibleCustomMetricsSourceIDs":[]}
        """
        let configuration = try JSONDecoder().decode(MetricsBarConfiguration.self, from: Data(json.utf8))
        #expect(configuration.showsKeyboardBattery == false)
        #expect(configuration.showsFan == false)
        #expect(configuration.showsNetwork)
    }

    @Test
    func keyboardBatteryConfiguration_decode_defaults_isEnabled_to_false_for_legacy_payloads() throws {
        let json = """
        {}
        """
        let configuration = try JSONDecoder().decode(KeyboardBatteryConfiguration.self, from: Data(json.utf8))
        #expect(configuration == KeyboardBatteryConfiguration(isEnabled: false))
    }

    @Test
    func keyboardBatteryInfo_encode_decode_roundtrips() throws {
        let info = BluetoothKeyboardInfo(
            id: "Keychron K6|ABC123",
            name: "Keychron K6",
            percent: 36,
            changedAt: Date(timeIntervalSince1970: 100),
            lastSeenAt: Date(timeIntervalSince1970: 200),
            status: .ok
        )
        let data = try JSONEncoder().encode(info)
        #expect(try JSONDecoder().decode(BluetoothKeyboardInfo.self, from: data) == info)
    }

    @Test
    func keyboardBatteryInfo_decodes_status_from_raw_value() throws {
        let json = """
        {"id":"k","name":"K6","percent":null,"changedAt":null,"lastSeenAt":null,"status":"needsPermission"}
        """
        let info = try JSONDecoder().decode(BluetoothKeyboardInfo.self, from: Data(json.utf8))
        #expect(info.status == .needsPermission)
        #expect(info.percent == nil)
    }
}
