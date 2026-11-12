/*
 NSWorkspaceClient.swift
 DataSource

 Created by Takuto Nakamura on 2026/05/05.
 Copyright 2026 Kyome22 (Takuto Nakamura)

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

import AppKit
import Combine

public struct NSWorkspaceClient: DependencyClient {
    public var open: @Sendable (URL) -> Bool
    public var urlForApplication: @Sendable (String) -> URL?
    public var openApplication: @Sendable (URL, NSWorkspace.OpenConfiguration) -> Void
    public var activateFileViewerSelecting: @Sendable ([URL]) -> Void
    public var post: @Sendable (Notification.Name, Any?) -> Void
    public var publisher: @Sendable (Notification.Name) -> AnyPublisher<Notification, Never>
    public var frontmostApplication: @Sendable () -> FrontmostApplicationInfo?
    public var frontmostApplicationChanges: @Sendable () -> AnyPublisher<FrontmostApplicationInfo?, Never>
    public var bundleIdentifier: @Sendable (URL) -> String?
    public var applicationName: @Sendable (String) -> String?
    public var applicationIcon: @Sendable (String) -> NSImage?

    public static let liveValue = Self(
        open: { NSWorkspace.shared.open($0) },
        urlForApplication: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
        openApplication: { NSWorkspace.shared.openApplication(at: $0, configuration: $1) },
        activateFileViewerSelecting: { NSWorkspace.shared.activateFileViewerSelecting($0) },
        post: { NSWorkspace.shared.notificationCenter.post(name: $0, object: $1) },
        publisher: { NSWorkspace.shared.notificationCenter.publisher(for: $0).eraseToAnyPublisher() },
        frontmostApplication: {
            guard let application = NSWorkspace.shared.frontmostApplication,
                  let bundleIdentifier = application.bundleIdentifier else { return nil }
            return FrontmostApplicationInfo(
                bundleIdentifier: bundleIdentifier,
                localizedName: application.localizedName ?? ""
            )
        },
        frontmostApplicationChanges: {
            NSWorkspace.shared.notificationCenter
                .publisher(for: NSWorkspace.didActivateApplicationNotification)
                .map { notification -> FrontmostApplicationInfo? in
                    guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                          let bundleIdentifier = application.bundleIdentifier else { return nil }
                    return FrontmostApplicationInfo(
                        bundleIdentifier: bundleIdentifier,
                        localizedName: application.localizedName ?? ""
                    )
                }
                .eraseToAnyPublisher()
        },
        bundleIdentifier: { Bundle(url: $0)?.bundleIdentifier },
        applicationName: { bundleIdentifier in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
            let bundle = Bundle(url: url)
            let name = bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String
                ?? bundle?.infoDictionary?["CFBundleDisplayName"] as? String
                ?? bundle?.infoDictionary?["CFBundleName"] as? String
            return name ?? url.deletingPathExtension().lastPathComponent
        },
        applicationIcon: { bundleIdentifier in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
            return NSWorkspace.shared.icon(forFile: url.path)
        }
    )

    public static let testValue = Self(
        open: { _ in false },
        urlForApplication: { _ in nil },
        openApplication: { _, _ in },
        activateFileViewerSelecting: { _ in },
        post: { _, _ in },
        publisher: { _ in Empty<Notification, Never>().eraseToAnyPublisher() },
        frontmostApplication: { nil },
        frontmostApplicationChanges: { Empty<FrontmostApplicationInfo?, Never>().eraseToAnyPublisher() },
        bundleIdentifier: { _ in nil },
        applicationName: { _ in nil },
        applicationIcon: { _ in nil }
    )
}

public struct FrontmostApplicationInfo: Sendable, Equatable {
    public let bundleIdentifier: String
    public let localizedName: String

    public init(bundleIdentifier: String, localizedName: String) {
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
    }
}
