// Copyright (c) 2018 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Combine
import Observation
import os

/// The system preference is independent of NSApp's explicit appearance.
/// Foundation exposes the global domain; the key and its Dark value are macOS
/// preference identifiers, so they stay at this external boundary.
enum SystemAppearancePreference {
	private static let interfaceStyleKey = "AppleInterfaceStyle"
	private enum InterfaceStyle: String {
		case dark = "Dark"
	}

	static func readMode() -> AppearanceMode {
		let domain = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
		return decode(interfaceStyle: domain?[interfaceStyleKey] as? String)
	}

	static func decode(interfaceStyle: String?) -> AppearanceMode {
		interfaceStyle.flatMap(InterfaceStyle.init(rawValue:)) == .dark ? .dark : .light
	}
}

/// A preview owns this read-only snapshot for as long as it is visible. It
/// never changes the app's appearance or commits the draft preference.
@Observable
final class SystemAppearanceSnapshot {
	private(set) var mode: AppearanceMode
	@ObservationIgnored private let readMode: @MainActor () -> AppearanceMode
	@ObservationIgnored private let notifications = NotificationSubscriptions()

	init(readMode: @escaping @MainActor () -> AppearanceMode = SystemAppearancePreference.readMode,
	     notificationCenter: NotificationCenter = .default)
	{
		self.readMode = readMode
		mode = readMode()
		for name in [UserDefaults.didChangeNotification, NSApplication.didBecomeActiveNotification] {
			notifications.observe(name, center: notificationCenter) { [weak self] _ in
				guard let self else { return }
				mode = self.readMode()
			}
		}
	}
}
