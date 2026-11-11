/*
 AITokenUsageCardView.swift
 UserInterface

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

import DataSource
import SwiftUI

extension AIToolKind {
    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .zcode: "ZCode"
        case .codex: "Codex CLI"
        }
    }
}

struct AITokenUsageCardView: View {
    var aiTokenUsage: AITokenUsage

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("aiTokenUsage", bundle: .module)
                Group {
                    ForEach(aiTokenUsage.tools) { tool in
                        Text(verbatim: "\(tool.kind.displayName): \(tool.counts.total.formattedTokenCount)")
                            .font(.caption)
                        BarGraphView(value: share(of: tool) * 100)
                    }
                    if aiTokenUsage.tools.isEmpty {
                        Text(verbatim: "0")
                            .font(.caption)
                    }
                }
                .padding(.leading, 12)
            }
        }
        .fixedSize()
        .padding(.leading, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .materialCellStyle()
    }

    private func share(of tool: AITokenUsage.Tool) -> Double {
        let total = aiTokenUsage.total.total
        guard total > 0 else {
            return 0
        }
        return Double(tool.counts.total) / Double(total)
    }
}
