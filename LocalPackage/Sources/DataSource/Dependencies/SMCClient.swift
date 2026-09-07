/*
 SMCClient.swift
 DataSource

 Created by ettingshausen on 2026/09/07.
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
import IOKit

public struct SMCClient: DependencyClient {
    public struct Reading: Sendable, Equatable {
        public var dataType: String
        public var dataBytes: [UInt8]

        public init(dataType: String, dataBytes: [UInt8]) {
            self.dataType = dataType
            self.dataBytes = dataBytes
        }
    }

    public var read: @Sendable (String) -> Reading?

    public static let liveValue = Self(
        read: { SMCConnection.shared.read($0) }
    )

    public static let testValue = Self(
        read: { _ in nil }
    )
}

private enum SMCFunctionCode: UInt8 {
    case readBytes = 5
    case readKeyInfo = 9
}

private struct SMCKeyData: Sendable {
    struct Version: Sendable {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct LimitData: Sendable {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct KeyInfo: Sendable {
        var dataSize: IOByteCount32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var version = Version()
    var pLimitData = LimitData()
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    ) = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}

private final class SMCConnection: @unchecked Sendable {
    static let shared = SMCConnection()

    private let lock: AllocatedUnfairLock<io_connect_t>

    private init() {
        var connection: io_connect_t = .zero
        var iterator: io_iterator_t = .zero
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSMC"), &iterator) == kIOReturnSuccess {
            let device = IOIteratorNext(iterator)
            if device != .zero {
                IOServiceOpen(device, mach_task_self_, 0, &connection)
                IOObjectRelease(device)
            }
            IOObjectRelease(iterator)
        }
        lock = AllocatedUnfairLock(initialState: connection)
    }

    func read(_ key: String) -> SMCClient.Reading? {
        guard key.count == 4 else { return nil }
        let keyAsCode = key.utf8.reduce(UInt32.zero) { $0 << 8 | UInt32($1) }
        return lock.withLock { connection -> SMCClient.Reading? in
            var input = SMCKeyData()
            var output = SMCKeyData()
            input.key = keyAsCode
            input.data8 = SMCFunctionCode.readKeyInfo.rawValue
            guard call(&connection, &input, &output) == kIOReturnSuccess,
                  output.keyInfo.dataSize > 0 else {
                return nil
            }
            let dataType = output.keyInfo.dataType.fourCharCode
            let dataSize = min(Int(output.keyInfo.dataSize), 32)
            input.keyInfo.dataSize = output.keyInfo.dataSize
            input.data8 = SMCFunctionCode.readBytes.rawValue
            guard call(&connection, &input, &output) == kIOReturnSuccess else {
                return nil
            }
            let bytes = withUnsafeBytes(of: &output.bytes) { Array($0.prefix(dataSize)) }
            return SMCClient.Reading(
                dataType: dataType,
                dataBytes: bytes
            )
        }
    }

    private func call(
        _ connection: inout io_connect_t,
        _ input: inout SMCKeyData,
        _ output: inout SMCKeyData
    ) -> kern_return_t {
        let size = MemoryLayout<SMCKeyData>.stride
        var outputSize = size
        return IOConnectCallStructMethod(
            connection,
            UInt32(2),
            &input,
            size,
            &output,
            &outputSize
        )
    }
}

private extension UInt32 {
    var fourCharCode: String {
        let scalars = [(self >> 24) & 0xff, (self >> 16) & 0xff, (self >> 8) & 0xff, self & 0xff]
        return String(bytes: scalars.map { UInt8($0) }, encoding: .ascii) ?? "????"
    }
}
