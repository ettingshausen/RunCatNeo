/*
 FanSectionView.swift
 UserInterface

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
import SwiftUI

struct FanSectionView: View {
    var fanInfo: FanInfo

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "fanblades")
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: summaryString)
                Group {
                    if fanInfo.fans.count > 1 {
                        ForEach(fanInfo.fans.indices, id: \.self) { index in
                            Text(verbatim: rowString(index))
                                .font(.caption)
                        }
                    }
                    if let normalizedRPM = normalizedRPM {
                        BarGraphView(value: normalizedRPM * 100)
                    }
                }
                .padding(.leading, 12)
            }
        }
        .fixedSize()
        .padding(.leading, 8)
    }

    private var summaryString: String {
        String(
            format: String(localized: "fanSummaryFormat", bundle: .module),
            Int(fanInfo.fans[0].rpm.rounded())
        )
    }

    private func rowString(_ index: Int) -> String {
        String(
            format: String(localized: "fanRowFormat", bundle: .module),
            index + 1,
            Int(fanInfo.fans[index].rpm.rounded())
        )
    }

    private var normalizedRPM: Double? {
        guard let maximumRPM = fanInfo.fans[0].maximumRPM, maximumRPM > 0 else {
            return nil
        }
        return min(max(fanInfo.fans[0].rpm / maximumRPM, .zero), 1)
    }
}
