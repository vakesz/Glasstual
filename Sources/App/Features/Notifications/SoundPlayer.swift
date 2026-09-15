/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import AudioToolbox
import os
import UniformTypeIdentifiers

/// Plays alert sounds by name and lists the ones a person can choose from.
@MainActor
enum SoundPlayer {
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "SoundPlayer"
	)

	/// The one sound that is not a file in a Sounds folder: the system alert,
	/// which `NSSound.beep()` plays and a notification names as its default.
	static let beepSoundName = "Beep"

	/** A SystemSoundID is an owned resource. Creating one per playback leaked it and
	 rescanned three sound directories on the notification-delivery path. */
	private static var soundCache: [String: SystemSoundID] = [:]

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

	static func playAlertSound(_ name: String) {
		if name == NotificationAlertSound.noSoundPreferenceValue {
			return
		}

		if name == beepSoundName {
			NSSound.beep()

			return
		}

		let soundID = cachedAlertSound(named: name)

		guard soundID != 0 else {
			logger.error("Unable to locate sound: \(name, privacy: .public)")

			return
		}

		AudioServicesPlayAlertSound(soundID)
	}

	/** The sound names a person can choose from, read from the three Sounds
	 folders the first time anything asks and kept for the rest of the launch.

	 The notification settings table asked for it every time its view was built,
	 which scanned three folders on the main actor on every redraw of its
	 parent. */
	static let availableSoundNames: [String] = uniqueListOfSounds()

	private static func uniqueListOfSounds() -> [String] {
		var sounds = [beepSoundName]

		for catalog in [systemAlertSoundFiles, systemLibrarySoundFiles, userLibrarySoundFiles] {
			for name in catalog?.keys ?? [String: String]().keys where !sounds.contains(name) {
				sounds.append(name)
			}
		}

		return sounds.sorted { first, second in
			first.caseInsensitiveCompare(second) == .orderedAscending
		}
	}

	private static var systemAlertSoundFiles: [String: String]? {
		soundFiles(in: .systemDomainMask)
	}

	private static var systemLibrarySoundFiles: [String: String]? {
		soundFiles(in: .localDomainMask)
	}

	private static var userLibrarySoundFiles: [String: String]? {
		soundFiles(in: .userDomainMask)
	}

	private static func soundFiles(in domain: FileManager.SearchPathDomainMask) -> [String: String]? {
		guard let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: domain).first else {
			return nil
		}

		return soundFiles(atPath: libraryURL.appending(path: "Sounds", directoryHint: .isDirectory).path)
	}

	/// Disposes every cached sound. Call once, during application termination.
	static func prepareForApplicationTermination() {
		for soundID in soundCache.values {
			AudioServicesDisposeSystemSoundID(soundID)
		}
		soundCache.removeAll()
	}

	private static func cachedAlertSound(named name: String) -> SystemSoundID {
		if let cached = soundCache[name] {
			return cached
		}
		let soundID = alertSound(named: name)
		if soundID != 0 {
			soundCache[name] = soundID
		}
		return soundID
	}

	private static func alertSound(named name: String) -> SystemSoundID {
		for catalog in [userLibrarySoundFiles, systemLibrarySoundFiles, systemAlertSoundFiles] {
			guard let soundPath = catalog?[name] else {
				continue
			}

			var soundID = SystemSoundID()
			let status = AudioServicesCreateSystemSoundID(URL(fileURLWithPath: soundPath) as CFURL, &soundID)

			if status == noErr {
				return soundID
			}

			logger.error("Unable to load sound at \(soundPath, privacy: .public), status: \(status)")
		}

		return 0
	}
}
