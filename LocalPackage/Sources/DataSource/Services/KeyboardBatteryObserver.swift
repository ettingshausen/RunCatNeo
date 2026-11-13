/*
 KeyboardBatteryObserver.swift
 DataSource

 Created by ettingshausen on 2026/11/11.
 Copyright 2026 ettingshausen

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

import AllocatedUnfairLock
import Foundation
import HIDShim
import IOKit.hid

/// An opened HID device and its battery element. The IOKit object types are
/// not Sendable, but every access is funneled through the observer's lock, so
/// the handle box opts out explicitly.
private struct DeviceHandle: @unchecked Sendable {
    let device: IOHIDDevice
    let element: IOHIDElement
    let buffer: UnsafeMutablePointer<UInt8>
    let deviceIdentity: UInt
}

/// Watches Bluetooth HID devices for the standard Battery Strength input
/// (Usage Page 0x06, Usage 0x20). Keychron's K6 declares it as input report 3;
/// the value only changes when the keyboard reconnects, so this is a
/// quasi-static metric: GET_REPORT always succeeds but returns the firmware's
/// cached report, and the keyboard never pushes the report on its own.
nonisolated final class KeyboardBatteryObserver: @unchecked Sendable {
    private struct Reading {
        var percent: Int
        var changedAt: Date?
        var lastSeenAt: Date
    }

    private struct DeviceState {
        var key: String
        var name: String
        var handle: DeviceHandle?
        var reading: Reading?
        var status: BluetoothKeyboardInfo.Status = .noReport
        var valueCapturedAt: Date?
        var freshReadInFlight = false
        /// The last scan-driven read. `scan()` runs once per HID entry and is
        /// also invoked for every device-matching callback, so without a guard
        /// a single launch would wake the keyboard dozens of times.
        var lastRefreshAt: Date?

        var info: BluetoothKeyboardInfo {
            BluetoothKeyboardInfo(
                id: key,
                name: name,
                percent: reading?.percent,
                changedAt: reading?.changedAt,
                lastSeenAt: reading?.lastSeenAt,
                status: status
            )
        }
    }

    private struct State: Sendable {
        var managerOpened = false
        var devices: [String: DeviceState] = [:]
        /// Survives disconnects: a reconnected keyboard needs a moment before it
        /// answers again, and keeping the last value avoids a visible blank.
        var lastReadings: [String: Reading] = [:]
        var infos: [BluetoothKeyboardInfo] = []
        var continuations: [UUID: AsyncStream<[BluetoothKeyboardInfo]>.Continuation] = [:]
    }

    static let shared = KeyboardBatteryObserver()

    /// ID of the synthetic row shown while Input Monitoring is denied, so the
    /// bar displays "--" instead of silently hiding the enabled feature.
    static let permissionHintID = "input-monitoring-required"

    private let manager: IOHIDManager
    private let lock: AllocatedUnfairLock<State>
    private var pollTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private static let pollInterval: Duration = .seconds(300)
    private static let retryInterval: Duration = .seconds(3)
    private static let reportBufferSize = 4096

    private init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        lock = AllocatedUnfairLock(initialState: State())
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerSetDeviceMatching(manager, nil)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, _ in
            guard let context else { return }
            Unmanaged<KeyboardBatteryObserver>.fromOpaque(context).takeUnretainedValue().scan()
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            let observer = Unmanaged<KeyboardBatteryObserver>.fromOpaque(context).takeUnretainedValue()
            observer.forget(device)
            observer.scan()
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    }

    var isAccessGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent).rawValue == 0
    }

    func requestAccess() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    func startMonitoring() {
        openManager()
        scan()
        startPolling()
        startRetrying()
    }

    /// Stops polling and drops every device handle. Handles go stale across
    /// sleep, and on reconnect macOS hands out brand-new IOHIDDevice objects,
    /// so a fresh open on the next start is what keeps readings following
    /// reality instead of pinning the pre-sleep value forever.
    func stopMonitoring() {
        pollTask?.cancel()
        pollTask = nil
        retryTask?.cancel()
        retryTask = nil
        lock.withLock { state in
            for (_, deviceState) in state.devices {
                if let handle = deviceState.handle {
                    IOHIDDeviceClose(handle.device, IOOptionBits(kIOHIDOptionsTypeNone))
                    handle.buffer.deallocate()
                }
            }
            state.devices.removeAll()
            state.lastReadings.removeAll()
            state.infos.removeAll()
            emit(&state)
        }
    }

    func stream() -> AsyncStream<[BluetoothKeyboardInfo]> {
        let id = UUID()
        return AsyncStream { continuation in
            let current = lock.withLock { state -> [BluetoothKeyboardInfo] in
                state.continuations[id] = continuation
                return state.infos
            }
            continuation.yield(current)
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { state in
                    state.continuations.removeValue(forKey: id)
                }
            }
        }
    }

    func currentValue() -> [BluetoothKeyboardInfo] {
        lock.withLock { $0.infos }
    }

    private func openManager() {
        let alreadyOpened = lock.withLock { $0.managerOpened }
        guard !alreadyOpened else { return }
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        lock.withLock { $0.managerOpened = (result == kIOReturnSuccess) }
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled else { break }
                self?.refreshAll()
                self?.scan()
            }
        }
    }

    /// A reconnected keyboard answers late, so a single failed read must not
    /// leave the row empty until the next five-minute poll.
    private func startRetrying() {
        guard retryTask == nil else { return }
        retryTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.retryInterval)
                guard !Task.isCancelled else { break }
                self?.refreshUnread()
            }
        }
    }

    private func refreshAll() {
        let handles = lock.withLock { state -> [(key: String, handle: DeviceHandle)] in
            state.devices.compactMap { key, deviceState in
                guard let handle = deviceState.handle else { return nil }
                return (key, handle)
            }
        }
        for entry in handles {
            refresh(handle: entry.handle, key: entry.key)
        }
    }

    private func refreshUnread() {
        let handles = lock.withLock { state -> [(key: String, handle: DeviceHandle)] in
            state.devices.compactMap { key, deviceState in
                guard let handle = deviceState.handle, deviceState.status != .ok else { return nil }
                return (key, handle)
            }
        }
        for entry in handles {
            refresh(handle: entry.handle, key: entry.key)
        }
    }

    private func refresh(handle: DeviceHandle, key: String) {
        if let cached = readCached(handle: handle) {
            adopt(value: cached.value, age: cached.age, key: key)
        }
        scheduleFreshRead(handle: handle, key: key)
    }

    private func forget(_ device: IOHIDDevice) {
        let deviceIdentity = UInt(bitPattern: UnsafeRawPointer(Unmanaged.passUnretained(device).toOpaque()))
        let staleHandle = lock.withLock { state -> DeviceHandle? in
            for (_, deviceState) in state.devices where deviceState.handle?.deviceIdentity == deviceIdentity {
                state.devices.removeValue(forKey: deviceState.key)
                return deviceState.handle
            }
            return nil
        }
        if let staleHandle {
            IOHIDDeviceClose(staleHandle.device, IOOptionBits(kIOHIDOptionsTypeNone))
            staleHandle.buffer.deallocate()
        }
    }

    private func scan() {
        guard let set = IOHIDManagerCopyDevices(manager) else { return }
        let count = CFSetGetCount(set)
        var raw = [UnsafeRawPointer?](repeating: nil, count: max(count, 1))
        CFSetGetValues(set, &raw)

        nonisolated(unsafe) var found: [BluetoothKeyboardInfo] = []
        for pointer in raw.prefix(count) {
            guard let pointer else { continue }
            let device = Unmanaged<IOHIDDevice>.fromOpaque(pointer).takeUnretainedValue()
            guard let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String,
                  transport == "Bluetooth" else {
                continue
            }
            let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "?"
            let serialNumber = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String ?? "?"
            let key = "\(product)|\(serialNumber)"
            let primaryUsagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int
            let primaryUsage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int
            let isKeyboardEntry = (primaryUsagePage == 1 && primaryUsage == 6)

            guard let elements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(0)) as? [IOHIDElement] else {
                // Keyboard-class devices need Input Monitoring before their
                // elements are readable; surface that instead of dropping the row.
                if isKeyboardEntry, !isAccessGranted {
                    found.append(BluetoothKeyboardInfo(id: key, name: product, status: .needsPermission))
                }
                continue
            }

            guard let element = elements.first(where: {
                IOHIDElementGetUsagePage($0) == 0x06 && IOHIDElementGetUsage($0) == 0x20
            }) else {
                // Many devices simply have no battery field; skip without error.
                continue
            }

            reopenIfNeeded(device: device, element: element, key: key, name: product)
            let shouldRefresh = lock.withLock { state -> Bool in
                guard state.devices[key] != nil else { return false }
                let now = Date()
                if let last = state.devices[key]?.lastRefreshAt,
                   now.timeIntervalSince(last) < 5 {
                    return false
                }
                state.devices[key]?.lastRefreshAt = now
                return true
            }
            if shouldRefresh, let handle = lock.withLock({ $0.devices[key]?.handle }) {
                refresh(handle: handle, key: key)
            }
            if let info = lock.withLock({ $0.devices[key]?.info }) {
                found.append(info)
            }
        }

        lock.withLock { state in
            // One physical device can surface several HID entries; keep one row per key.
            var deduplicated: [String: BluetoothKeyboardInfo] = [:]
            for info in found {
                if let existing = deduplicated[info.id] {
                    deduplicated[info.id] = BluetoothKeyboardInfo(
                        id: info.id,
                        name: existing.percent != nil ? existing.name : info.name,
                        percent: existing.percent ?? info.percent,
                        changedAt: existing.changedAt ?? info.changedAt,
                        lastSeenAt: existing.lastSeenAt ?? info.lastSeenAt,
                        status: existing.status == .ok ? .ok : info.status
                    )
                } else {
                    deduplicated[info.id] = info
                }
            }
            // With Input Monitoring denied, keyboard entries cannot be inspected
            // at all; surface a hint row so the bar shows "--" instead of
            // silently hiding the feature the user just enabled.
            if !isAccessGranted, deduplicated.values.allSatisfy({ $0.status != .ok }) {
                deduplicated[Self.permissionHintID] = BluetoothKeyboardInfo(
                    id: Self.permissionHintID,
                    name: "keyboard",
                    status: .needsPermission
                )
            }
            state.infos = deduplicated.values.sorted { $0.name < $1.name }
            emit(&state)
        }
    }

    private func reopenIfNeeded(device: IOHIDDevice, element: IOHIDElement, key: String, name: String) {
        let deviceIdentity = UInt(bitPattern: UnsafeRawPointer(Unmanaged.passUnretained(device).toOpaque()))
        let staleHandle = lock.withLock { state -> DeviceHandle? in
            guard let held = state.devices[key]?.handle else { return nil }
            // A reconnected keyboard arrives as a NEW IOHIDDevice object.
            // Comparing identity — not just "is there a handle" — is what
            // makes the reading follow the reconnect.
            guard held.deviceIdentity != deviceIdentity else { return nil }
            state.devices.removeValue(forKey: key)
            return held
        }
        if let staleHandle {
            IOHIDDeviceClose(staleHandle.device, IOOptionBits(kIOHIDOptionsTypeNone))
            staleHandle.buffer.deallocate()
        }
        if lock.withLock({ $0.devices[key] != nil }) { return }

        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        let newHandle: DeviceHandle? = {
            guard result == kIOReturnSuccess else { return nil }
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.reportBufferSize)
            return DeviceHandle(
                device: device,
                element: element,
                buffer: buffer,
                deviceIdentity: deviceIdentity
            )
        }()
        lock.withLock { state in
            guard state.devices[key] == nil else { return }
            state.devices[key] = DeviceState(
                key: key,
                name: name,
                handle: newHandle,
                // Keep the last known reading across the reconnect: the firmware
                // needs a moment before it answers with a new sample.
                reading: state.lastReadings[key],
                status: result == kIOReturnNotPermitted ? .needsPermission : .noReport
            )
        }
        if newHandle != nil {
            installInputReportHook(device: device, context: Unmanaged.passUnretained(self).toOpaque())
        }
    }

    private func installInputReportHook(device: IOHIDDevice, context: UnsafeMutableRawPointer) {
        let key = Self.key(for: device)
        let handle = lock.withLock { $0.devices[key]?.handle }
        guard let buffer = handle?.buffer else { return }
        IOHIDDeviceRegisterInputReportCallback(device, buffer, Self.reportBufferSize, { context, result, sender, _, reportID, report, reportLength in
            guard result == kIOReturnSuccess, let context, let sender,
                  reportID == 3, reportLength >= 1 else { return }
            // The pushed payload excludes the report ID byte, so the battery is report[0].
            let percent = Int(report[0])
            guard (1...100).contains(percent) else { return }
            let observer = Unmanaged<KeyboardBatteryObserver>.fromOpaque(context).takeUnretainedValue()
            let key = KeyboardBatteryObserver.key(for: Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue())
            observer.adopt(value: percent, age: 0, key: key)
        }, context)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    }

    private static func key(for device: IOHIDDevice) -> String {
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "?"
        let serialNumber = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String ?? "?"
        return "\(product)|\(serialNumber)"
    }

    private func readCached(handle: DeviceHandle) -> (value: Int, age: UInt64)? {
        var value: Int32 = -1
        var age: UInt64 = 0
        guard KBHIDReadCachedValueEx(handle.device, handle.element, &value, &age) == kIOReturnSuccess else { return nil }
        guard (1...100).contains(Int(value)) else { return nil }
        return (Int(value), age)
    }

    /// GET_REPORT blocks until the keyboard answers, so it runs off the main thread.
    private func scheduleFreshRead(handle: DeviceHandle, key: String) {
        let shouldSchedule = lock.withLock { state -> Bool in
            if state.devices[key]?.freshReadInFlight == true { return false }
            state.devices[key]?.freshReadInFlight = true
            return true
        }
        guard shouldSchedule else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            var value: Int32 = -1
            var age: UInt64 = 0
            let result = KBHIDReadFreshValueEx(handle.device, handle.element, &value, &age)
            self.lock.withLock { $0.devices[key]?.freshReadInFlight = false }
            guard result == kIOReturnSuccess, (1...100).contains(Int(value)) else { return }
            self.adopt(value: Int(value), age: age, key: key)
        }
    }

    /// Keeps whichever reading came from the newest report, and records when the
    /// value actually changed — the honest description of a quasi-static metric.
    ///
    /// Freshness is compared by the report's absolute capture time, not by the
    /// age alone: the same cached report is answered again on every read, so its
    /// age grows monotonically and an "is this age smaller" test would reject
    /// every observation after the first one, freezing the readout at the value
    /// seen when the app launched.
    private func adopt(value: Int, age: UInt64, key: String) {
        let changed = lock.withLock { state -> Bool in
            guard var deviceState = state.devices[key] else { return false }
            let capturedAt = Date().addingTimeInterval(-Double(age))
            if let existingCapturedAt = deviceState.valueCapturedAt,
               existingCapturedAt >= capturedAt.addingTimeInterval(-0.5),
               deviceState.reading?.percent == value {
                return false
            }
            deviceState.valueCapturedAt = capturedAt
            let previous = deviceState.reading?.percent
            let now = Date()
            var reading = deviceState.reading ?? Reading(percent: value, changedAt: nil, lastSeenAt: now)
            if previous != value || reading.changedAt == nil {
                reading.changedAt = now
            }
            reading.percent = value
            reading.lastSeenAt = now
            deviceState.reading = reading
            deviceState.status = .ok
            state.devices[key] = deviceState
            state.lastReadings[key] = reading
            if let index = state.infos.firstIndex(where: { $0.id == key }) {
                state.infos[index] = deviceState.info
            }
            return previous != value || previous == nil
        }
        if changed {
            emitAll()
        }
    }

    private func emitAll() {
        lock.withLock { state in
            emit(&state)
        }
    }

    private func emit(_ state: inout State) {
        let infos = state.infos
        for continuation in state.continuations.values {
            continuation.yield(infos)
        }
    }
}
