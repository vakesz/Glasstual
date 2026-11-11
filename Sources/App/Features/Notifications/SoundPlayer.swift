// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import os

/// Plays alert sounds by name.
///
/// `/notifysound` is what asks for one. A notification carries the system alert
/// instead, so that Do Not Disturb and the alert volume apply to it.
@MainActor
enum SoundPlayer {
	private static let logger = Logger(
		subsystem: LogSubsystem.current,
		category: "SoundPlayer"
	)

	/// The one sound that is not a file in a Sounds folder: the system alert,
	/// which `NSSound.beep()` plays.
	static let beepSoundName = "Beep"

	/** Plays the named sound.

	 `NSSound(named:)` searches the three Sounds folders itself and keeps what it
	 loads, which is what the hand-rolled `SystemSoundID` cache and its
	 termination hook were for. */
	static func playAlertSound(_ name: String) {
		guard name != beepSoundName else {
			NSSound.beep()
			return
		}

		guard let sound = NSSound(named: name) else {
			logger.error("Unable to locate sound: \(name, privacy: .public)")
			return
		}

		sound.play()
	}
}
