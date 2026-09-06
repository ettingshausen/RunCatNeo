/*
 SMCClient+Extension.swift
 Model

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

import DataSource

extension SMCClient.Reading {
    var numberValue: Double? {
        switch dataType {
        case "ui8 ":
            guard dataBytes.count >= 1 else { return nil }
            return Double(dataBytes[0])
        case "ui16":
            guard dataBytes.count >= 2 else { return nil }
            return Double(UInt16(dataBytes[0]) << 8 | UInt16(dataBytes[1]))
        case "ui32":
            guard dataBytes.count >= 4 else { return nil }
            return Double(
                UInt32(dataBytes[0]) << 24
                    | UInt32(dataBytes[1]) << 16
                    | UInt32(dataBytes[2]) << 8
                    | UInt32(dataBytes[3])
            )
        case "flt ":
            guard dataBytes.count >= 4 else { return nil }
            return dataBytes.withUnsafeBufferPointer {
                $0.baseAddress?.withMemoryRebound(to: Float.self, capacity: 1) { Double($0.pointee) }
            }
        case "fpe2":
            guard dataBytes.count >= 2 else { return nil }
            return Double((Int(dataBytes[0]) << 6) + (Int(dataBytes[1]) >> 2))
        default:
            return nil
        }
    }
}
