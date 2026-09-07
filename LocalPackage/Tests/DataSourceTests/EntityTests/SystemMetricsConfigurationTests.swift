import Foundation
import Testing

@testable import DataSource

struct SystemMetricsConfigurationTests {
    @Test
    func decode_defaults_monitorsFan_to_true_for_legacy_payloads() throws {
        let json = """
        {"monitorsMemory":true,"monitorsStorage":false,"monitorsBattery":true,"monitorsNetwork":true}
        """
        let configuration = try JSONDecoder().decode(SystemMetricsConfiguration.self, from: Data(json.utf8))
        #expect(configuration == SystemMetricsConfiguration(
            monitorsMemory: true,
            monitorsStorage: false,
            monitorsBattery: true,
            monitorsNetwork: true
        ))
    }

    @Test
    func encode_decode_roundtrips_monitorsFan_false() throws {
        var configuration = SystemMetricsConfiguration.default
        configuration.monitorsFan = false
        let data = try JSONEncoder().encode(configuration)
        #expect(try JSONDecoder().decode(SystemMetricsConfiguration.self, from: data) == configuration)
    }
}
