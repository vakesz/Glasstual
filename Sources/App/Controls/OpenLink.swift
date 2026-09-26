// Copyright (c) 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation
import os

private let openLinkLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "OpenLink"
)

enum OpenLink {
	/** Hands a URL the allowlist has already cleared to the system.

	 `NSWorkspace` launches whatever app has registered the scheme, so this is
	 the last step of a launch a remote peer asked for. It is a stored value
	 rather than a call so that ``opener`` can stand somewhere else in a test. */
	static let workspaceOpener: @MainActor (URL, Bool) -> Void = { url, inBackground in
		guard inBackground else {
			NSWorkspace.shared.open(url)

			return
		}

		/* User should not be clicking links frequently enough that
		 we need to worry about making the configuration static. */
		let configuration = NSWorkspace.OpenConfiguration()
		configuration.activates = false

		NSWorkspace.shared.open(url, configuration: configuration)
	}

	/** Where a URL goes once ``open(url:inBackground:)`` has cleared it.

	 The guard in front of this is the only thing between a string a stranger
	 typed in a conversation and an app launch on this machine, so a test has to be
	 able to prove that the guard refuses what it should and passes what it
	 should -- without asking the real workspace to open `file:///etc/passwd` to
	 find out. Tests substitute their own opener and restore
	 ``workspaceOpener``; nothing in the app replaces it. */
	static var opener = workspaceOpener

	static func open(url: URL, inBackground: Bool = SettingsKeys.Messages.openBrowserInBackground.value) {
		/* Links come from other people. `NSWorkspace` launches whatever app has
		 registered the scheme, so the same allowlist that decides what becomes
		 clickable also decides what may be opened: no caller is trusted to have
		 filtered already. */
		guard let scheme = url.scheme, LinkSchemeRules.current().permits(scheme: scheme) else {
			openLinkLogger.info("Refused to open URL with scheme '\(url.scheme ?? "(none)", privacy: .public)'")

			return
		}

		opener(url, inBackground)
	}

	static func open(string: String, inBackground: Bool = SettingsKeys.Messages.openBrowserInBackground.value) {
		guard let urlToOpen = URL(string: string) else {
			return
		}

		open(url: urlToOpen, inBackground: inBackground)
	}
}
