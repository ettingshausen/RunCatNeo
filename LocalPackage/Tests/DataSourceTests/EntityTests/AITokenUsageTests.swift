/*
 AITokenUsageTests.swift
 DataSourceTests

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

import Foundation
import Testing

@testable import DataSource

struct AITokenUsageTests {
    @Test
    func aiTokenUsageConfiguration_missing_key_decodes_as_disabled() throws {
        let json = Data("{}".utf8)
        let configuration = try JSONDecoder().decode(AITokenUsageConfiguration.self, from: json)
        #expect(configuration == .default)
        #expect(!configuration.isEnabled)
    }

    @Test
    func aiTokenUsageConfiguration_roundtrips_enabled_state() throws {
        let configuration = AITokenUsageConfiguration(isEnabled: true)
        let data = try JSONEncoder().encode(configuration)
        #expect(try JSONDecoder().decode(AITokenUsageConfiguration.self, from: data) == configuration)
    }

    @Test
    func metricsBarConfiguration_without_ai_key_decodes_showsAITokenUsage_false() throws {
        let json = Data("""
            {
              "showsCPU": true,
              "showsMemory": false,
              "showsStorage": false,
              "showsBattery": false,
              "showsNetwork": false,
              "visibleCustomMetricsSourceIDs": []
            }
            """.utf8)
        let configuration = try JSONDecoder().decode(MetricsBarConfiguration.self, from: json)
        #expect(!configuration.showsAITokenUsage)
        #expect(configuration.showsCPU)
    }

    @Test
    func metricsBarConfiguration_isEmpty_includes_ai_token_usage() {
        var configuration = MetricsBarConfiguration(
            showsCPU: false,
            showsMemory: false,
            showsStorage: false,
            showsBattery: false,
            showsNetwork: false,
            visibleCustomMetricsSourceIDs: []
        )
        #expect(configuration.isEmpty)
        configuration.showsAITokenUsage = true
        #expect(!configuration.isEmpty)
    }

    @Test
    func formattedTokenCount_abbreviates_large_counts() {
        #expect(912.formattedTokenCount == "912")
        #expect(1_000.formattedTokenCount == "1K")
        #expect(1_234.formattedTokenCount == "1.2K")
        #expect(1_500_000.formattedTokenCount == "1.5M")
        #expect(88_442_571.formattedTokenCount == "88.4M")
        #expect(141_959_214.formattedTokenCount == "142M")
        #expect(1_230_000_000.formattedTokenCount == "1.2B")
        #expect((-5).formattedTokenCount == "0")
    }

    @Test
    func aiTokenUsage_init_drops_empty_tools_sorts_by_total_and_sums() {
        let claude = AITokenUsage.Tool(
            kind: .claudeCode,
            counts: .init(input: 10, output: 5, cacheRead: 3, cacheWrite: 2)
        )
        let zcode = AITokenUsage.Tool(kind: .zcode, counts: .init(input: 100, output: 20))
        let codex = AITokenUsage.Tool(kind: .codex, counts: .init())
        let usage = AITokenUsage(tools: [claude, codex, zcode], updatedAt: Date(timeIntervalSince1970: 100))
        #expect(usage.tools.map(\.kind) == [.zcode, .claudeCode])
        #expect(usage.total.total == 140)
        #expect(usage.barLabel == "140")
    }
}
