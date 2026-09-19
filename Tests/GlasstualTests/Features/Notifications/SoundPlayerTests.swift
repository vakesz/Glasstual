// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Notification sounds")
struct SoundPlayerTests {
	@Test("Sounds are keyed by name, and a name claimed twice keeps one file")
	func soundFileDiscoveryMapsNamesAndKeepsOneFilePerName() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("GlasstualSoundTests-\(UUID().uuidString)", isDirectory: true)

		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		try Data().write(to: directory.appendingPathComponent("Ping.aiff"))
		try Data().write(to: directory.appendingPathComponent("Tone.aiff"))
		try Data().write(to: directory.appendingPathComponent("Tone.wav"))
		/* A Sounds folder holds more than sounds. None of these may reach the
		 picker as a sound that plays nothing. */
		try Data().write(to: directory.appendingPathComponent(".DS_Store"))
		try Data().write(to: directory.appendingPathComponent(".Hidden.aiff"))
		try Data().write(to: directory.appendingPathComponent("Read Me.txt"))
		try FileManager.default.createDirectory(
			at: directory.appendingPathComponent("Folder", isDirectory: true),
			withIntermediateDirectories: false
		)

		let sounds = SoundPlayer.soundFiles(atPath: directory.path)

		#expect(sounds["Ping"] == directory.appendingPathComponent("Ping.aiff").path)
		#expect(sounds["Tone"] != nil)
		#expect(sounds.count == 2)
	}

	@Test("The list offered to the user contains Beep and is sorted ignoring case")
	func uniqueSoundListContainsBeepAndIsCaseInsensitivelySorted() {
		let sounds = SoundPlayer.availableSoundNames
		let sortedSounds = sounds.sorted { $0.caseInsensitiveCompare($1) == .orderedAscending }

		#expect(sounds.contains("Beep"))
		#expect(sounds == sortedSounds)
	}
}
