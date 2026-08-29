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
import Synchronization
import UniformTypeIdentifiers

public final class SoundPlayer: NSObject {
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "SoundPlayer"
	)

	/** A SystemSoundID is an owned resource. Creating one per playback leaked it and
	 rescanned three sound directories on the notification-delivery path. */
	private static let soundCache = Mutex<[String: SystemSoundID]>([:])

	public static func soundFiles(atPath path: String) -> [String: String] {
		let files = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
		var sounds: [String: String] = [:]

		for file in files {
			let filePath = (path as NSString).appendingPathComponent(file)
			let name = (file as NSString).deletingPathExtension

			sounds[name] = filePath
		}

		return sounds
	}

	public static func playAlertSound(_ name: String) {
		if name == NotificationAlertSound.noSoundPreferenceValue {
			return
		}

		if name == "Beep" {
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

	public static func uniqueListOfSounds() -> [String] {
		var sounds = ["Beep"]

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
	public static func prepareForApplicationTermination() {
		soundCache.withLock { cache in
			for soundID in cache.values {
				AudioServicesDisposeSystemSoundID(soundID)
			}

			cache.removeAll()
		}
	}

	private static func cachedAlertSound(named name: String) -> SystemSoundID {
		soundCache.withLock { cache in
			if let cached = cache[name] {
				return cached
			}

			let soundID = alertSound(named: name)

			if soundID != 0 {
				cache[name] = soundID
			}

			return soundID
		}
	}

	private static func alertSound(named name: String) -> SystemSoundID {
		for catalog in [userLibrarySoundFiles, systemLibrarySoundFiles, systemAlertSoundFiles] {
			guard let catalog, let soundPath = validatedSoundPath(named: name, in: catalog) else {
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

	private static func validatedSoundPath(named name: String, in files: [String: String]) -> String? {
		guard let path = files[name] else {
			return nil
		}

		guard
			let type = UTType(filenameExtension: (path as NSString).pathExtension),
			type.conforms(to: .audio)
		else {
			logger.debug("File is not audio: \(path, privacy: .public)")

			return nil
		}

		return path
	}
}
