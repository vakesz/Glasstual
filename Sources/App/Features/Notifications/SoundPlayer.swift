// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import os
import UniformTypeIdentifiers

/// Plays alert sounds by name and lists the ones a person can choose from.
///
/// `/notifysound` is what asks for one. A notification carries the system alert
/// instead, so that Do Not Disturb and the alert volume apply to it.
@MainActor
enum SoundPlayer {
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "SoundPlayer"
	)

	/// The one sound that is not a file in a Sounds folder: the system alert,
	/// which `NSSound.beep()` plays.
	static let beepSoundName = "Beep"

	/** The sound files in the folder at `path`, keyed by name without the
	 extension.

	 Only audio files count. A Sounds folder can also hold a `.DS_Store`, a
	 read-me or a folder, and each of those used to appear in the sound picker
	 as a sound that played nothing. */
	static func soundFiles(atPath path: String) -> [String: String] {
		let files = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
		var sounds: [String: String] = [:]

		for file in files.sorted() where file.hasPrefix(".") == false {
			guard let type = UTType(filenameExtension: (file as NSString).pathExtension), type.conforms(to: .audio)
			else {
				continue
			}

			sounds[(file as NSString).deletingPathExtension] = (path as NSString).appendingPathComponent(file)
		}

		return sounds
	}

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

	/** The sound names a person can choose from, read from the three Sounds
	 folders the first time anything asks and kept for the rest of the launch. */
	static let availableSoundNames: [String] = uniqueListOfSounds()

	private static func uniqueListOfSounds() -> [String] {
		var sounds = [beepSoundName]

		for domain in [FileManager.SearchPathDomainMask.systemDomainMask, .localDomainMask, .userDomainMask] {
			for name in soundFiles(in: domain)?.keys ?? [String: String]().keys where !sounds.contains(name) {
				sounds.append(name)
			}
		}

		return sounds.sorted { first, second in
			first.caseInsensitiveCompare(second) == .orderedAscending
		}
	}

	private static func soundFiles(in domain: FileManager.SearchPathDomainMask) -> [String: String]? {
		guard let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: domain).first else {
			return nil
		}

		return soundFiles(atPath: libraryURL.appending(path: "Sounds", directoryHint: .isDirectory).path)
	}
}
