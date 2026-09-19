// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** What the reader asked not to see again, and the answer they gave when they
 asked it.

 The flag and the response live beside each other in the alert suppression
 family, so both stay out of an export. Showing an alert is `Alerts`'s job;
 remembering the ones that are not shown is this one's. */
enum AlertSuppression {
	private static let suppressionPrefix = SettingsKeys.Families.alertSuppression.pattern

	/// Distinguishes the flag from the response recorded beside it.
	private static var responseSuffix: String {
		" -> Response"
	}

	/// Whether the user has previously chosen "do not show again" for an alert
	/// whose suppression key was `baseKey`.
	static func isSuppressed(baseKey: String) -> Bool {
		isSuppressed(fullKey: suppressionKey(withBase: baseKey))
	}

	/// The button a suppressed alert answers with, or `nil` when the user has
	/// not chosen to stop seeing it.
	static func suppressedResponse(baseKey: String) -> AlertResponse? {
		recordedResponse(fullKey: suppressionKey(withBase: baseKey))
	}

	static func isSuppressed(fullKey: String) -> Bool {
		suppressionFlag(fullKey).value
	}

	static func recordedResponse(fullKey: String) -> AlertResponse? {
		guard isSuppressed(fullKey: fullKey) else {
			return nil
		}

		return suppressionResponse(fullKey).value
	}

	/// Remembers that `fullKey`'s alert is not to be shown again, and which
	/// button answered it when the checkbox was ticked.
	static func record(_ response: AlertResponse, fullKey: String) {
		suppressionFlag(fullKey).value = true
		suppressionResponse(fullKey).value = response
	}

	static func suppressionKey(withBase base: String) -> String {
		if base.hasPrefix(suppressionPrefix) {
			return base
		}

		return suppressionPrefix + base
	}

	/** The flag goes to the container, which is what the suppression family is
	 catalogued under, so an imported "do not ask again" reaches the store the
	 alert reads. */
	private static func suppressionFlag(_ fullKey: String) -> SettingsKey<Bool> {
		SettingsKey(fullKey, default: false, traits: [.unregistered, .uncatalogued])
	}

	/** Which button was pressed when the checkbox was ticked.

	 Recording only *that* an alert was suppressed would make every later run
	 answer with the default button, so a suppressed "No" would open the link or
	 delete the channel anyway. A flag with no answer beside it -- which only a
	 hand-edited plist holds, since `record(_:fullKey:)` writes both -- falls
	 back to the default button. */
	private static func suppressionResponse(_ fullKey: String) -> SettingsKey<AlertResponse> {
		SettingsKey(fullKey + responseSuffix, default: .default, traits: [.unregistered, .uncatalogued])
	}
}
