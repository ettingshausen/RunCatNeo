/*
 StockClient.swift
 DataSource

 Created by ettingshausen on 2026/11/13.
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

import Foundation

public struct StockClient: DependencyClient {
    /// Fetches the quotes for the given Sina codes in one request and returns
    /// the raw response body decoded from GBK.
    public var fetch: @Sendable ([String]) async throws -> String

    public static let liveValue = Self(
        fetch: { symbols in
            guard !symbols.isEmpty else { return "" }
            var request = URLRequest(url: URL(string: "https://hq.sinajs.cn/list=\(symbols.joined(separator: ","))")!)
            request.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
            let (data, _) = try await URLSession.shared.data(for: request)
            // Sina answers in GBK; Foundation exposes the conversion via
            // CFString's encoding registry.
            let gbk = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            ))
            return String(data: data, encoding: gbk)
                ?? String(data: data, encoding: .utf8)
                ?? ""
        }
    )

    public static let testValue = Self(
        fetch: { _ in throw URLError(.unsupportedURL) }
    )
}
