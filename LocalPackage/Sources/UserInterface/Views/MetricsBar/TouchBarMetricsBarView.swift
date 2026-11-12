/*
 TouchBarMetricsBarView.swift
 UserInterface

 Created by ettingshausen on 2026/11/12.
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
import Model
import SwiftUI

/// The metrics bar rendered natively for the Touch Bar: vector SF Symbols and
/// text laid out over the always-on OLED panel. The visible metrics come
/// pre-decided from the store's `touchBarIndicators`.
public struct TouchBarMetricsBarView: View {
    @StateObject private var store: MetricsBar

    public init(_ appDependencies: AppDependencies) {
        _store = StateObject(wrappedValue: MetricsBar(appDependencies))
    }

    public var body: some View {
        let indicators = store.touchBarIndicators
        return HStack(spacing: 10) {
            if indicators.isEmpty {
                Image(systemName: "moon.zzz")
                    .foregroundStyle(.white)
            } else {
                ForEach(Array(indicators.enumerated()), id: \.offset) { _, indicator in
                    HStack(spacing: 3) {
                        Image(systemName: indicator.systemIcon)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 13)
                        if let secondaryText = indicator.secondaryText {
                            VStack(spacing: 1) {
                                Text(verbatim: indicator.primaryText)
                                    .font(.system(size: 8))
                                    .monospacedDigit()
                                    .lineLimit(1)
                                Text(verbatim: secondaryText)
                                    .font(.system(size: 8))
                                    .monospacedDigit()
                                    .lineLimit(1)
                            }
                            .fixedSize()
                        } else {
                            Text(verbatim: indicator.primaryText)
                                .font(.system(size: 12))
                                .monospacedDigit()
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    .foregroundStyle(.white)
                    .fixedSize()
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .fixedSize(horizontal: true, vertical: false)
        .background(Color(nsColor: NSColor(calibratedWhite: 0.1, alpha: 1)))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .task {
            await store.send(.viewAppeared(String(describing: Self.self)))
        }
        .onDisappear {
            Task {
                await store.send(.viewDisappeared)
            }
        }
    }
}
