import AllocatedUnfairLock
import Foundation
import Testing

@testable import DataSource
@testable import Model

struct KeyboardBatteryServiceTests {
    @Test
    func updateMetrics_pushes_keyboard_batteries_to_app_state() {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let sut = KeyboardBatteryService(.testDependencies(appStateClient: .testDependency(appState)))
        let infos = [
            BluetoothKeyboardInfo(id: "Keychron K6|ABC", name: "Keychron K6", percent: 36, status: .ok),
        ]
        sut.updateMetrics(from: infos)
        #expect(appState.withLock(\.keyboardBatteries.latestValue) == infos)
        #expect(appState.withLock(\.metrics.latestValue)?.keyboardBatteries == infos)
    }

    @Test
    func updateMetrics_clears_keyboard_batteries_with_empty_array() {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let sut = KeyboardBatteryService(.testDependencies(appStateClient: .testDependency(appState)))
        sut.updateMetrics(from: [BluetoothKeyboardInfo(id: "k", name: "K6", percent: 36, status: .ok)])
        sut.updateMetrics(from: [])
        #expect(appState.withLock(\.keyboardBatteries.latestValue) == [])
        #expect(appState.withLock(\.metrics.latestValue)?.keyboardBatteries == [])
    }
}
