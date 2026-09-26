// Copyright (c) 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Which schemes beyond the built-in ones the reader allows.

 The declarations keep the key names the AutoHyperlinks framework that preceded
 this parser used, so a user customization carries over. */
nonisolated struct LinkSchemeRules: Sendable {
	var permitsAnyScheme = false
	var permittedSchemes: Set<String> = []

	/// The allowlist the reader's settings describe right now.
	@MainActor static func current() -> LinkSchemeRules {
		LinkSchemeRules(
			permitsAnyScheme: SettingsKeys.LinkSchemes.permitAny.value,
			permittedSchemes: Set(SettingsKeys.LinkSchemes.permittedDefault.value)
				.union(SettingsKeys.LinkSchemes.permitted.value)
		)
	}

	/// The two schemes a link the app opens itself is written in.
	static let webSchemes: Set<String> = ["http", "https"]

	/// The app's own scheme, which a link may carry back into the app.
	static let appSchemes: Set<String> = ["glasstual"]

	/// Schemes that are always linked, regardless of user settings.
	private static let builtInSchemes: Set<String> = webSchemes.union([
		"xmpp",
		"rdar", "radr", "radar", "x-radar",
		"spotify", "dict", "magnet", "message",
	])

	/** Schemes that hand a remote peer's string to the file system, a network
	 mount, a system settings pane or an interpreter. They are refused ahead of
	 the user customization keys below so that a permissive `permitsAnyScheme`
	 cannot re-enable them. */
	private static let deniedSchemes: Set<String> = [
		"file",
		"smb", "afp", "nfs", "cifs",
		"x-apple.systempreferences",
		"javascript", "data", "vbscript", "blob", "filesystem", "about",
	]

	/// Whether `url` addresses a host over HTTP(S), which is the only shape an
	/// inline image may be fetched from.
	static func isWebURL(_ url: URL) -> Bool {
		webSchemes.contains(url.scheme?.lowercased() ?? "") && url.host?.isEmpty == false
	}

	/// Whether the app hands `url` straight to the system rather than offering
	/// it to a channel- or nickname-specific action first.
	static func opensDirectly(_ url: URL) -> Bool {
		let scheme = url.scheme?.lowercased() ?? ""
		return webSchemes.contains(scheme) || appSchemes.contains(scheme)
	}

	/// Whether a scheme may be linked, and may be handed to `NSWorkspace`.
	///
	/// - Parameters:
	///   - scheme: A URL scheme, without the trailing colon.
	func permits(scheme: String) -> Bool {
		let scheme = scheme.lowercased()

		if Self.deniedSchemes.contains(scheme) {
			return false
		}

		if Self.builtInSchemes.contains(scheme) {
			return true
		}

		return permitsAnyScheme || permittedSchemes.contains(scheme)
	}

	/// The same answer for a whole address, which is what a rendered run and a
	/// drawn topic carry.
	func permits(link location: String) -> Bool {
		guard let url = URL(string: location), let scheme = url.scheme else { return false }
		return permits(scheme: scheme)
	}
}
