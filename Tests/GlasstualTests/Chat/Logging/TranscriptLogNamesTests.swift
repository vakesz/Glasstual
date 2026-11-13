// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
@Suite("Transcript log names")
struct TranscriptLogNamesTests {
	@Test("A day is read back from the file name the writer gives it")
	func dayRoundTripsThroughItsFilename() throws {
		let day = try #require(TranscriptDay(filename: "2026-03-07.txt"))

		#expect(day == TranscriptDay(year: 2026, month: 3, day: 7))
		#expect(day.filename == "2026-03-07.txt")
	}

	@Test(
		"Files that are not a day's transcript are not days",
		arguments: ["notes.txt", "2026-3-7.txt", "2026-13-01.txt", "2026-01-00.txt", "2026-01-01.log", "2026-01-01", ".txt"]
	)
	func otherFilesAreNotDays(filename: String) {
		#expect(TranscriptDay(filename: filename) == nil)
	}

	@Test("Days sort by year, then month, then day")
	func daysAreOrdered() {
		let days = [
			TranscriptDay(year: 2026, month: 2, day: 1),
			TranscriptDay(year: 2025, month: 12, day: 31),
			TranscriptDay(year: 2026, month: 1, day: 30),
		]

		#expect(days.sorted().map(\.filename) == ["2025-12-31.txt", "2026-01-30.txt", "2026-02-01.txt"])
	}

	@Test("A connection folder is split into its name and identifier prefix")
	func serverFolderIsSplit() {
		let folder = TranscriptServerFolder(folderName: "Libera Chat (1a2b3)")

		#expect(folder.name == "Libera Chat")
		#expect(folder.identifier == "1a2b3")
	}

	@Test("A folder the application did not name keeps its whole name", arguments: ["Libera", "Libera (home)", "Libera (1a2b3"])
	func foreignServerFolderIsKept(name: String) {
		let folder = TranscriptServerFolder(folderName: name)

		#expect(folder.name == name)
		#expect(folder.identifier.isEmpty)
	}

	@Test("The folders the writer uses name the kinds the viewer reads", arguments: TranscriptKind.allCases)
	func kindsRoundTripThroughFolderNames(kind: TranscriptKind) {
		#expect(TranscriptKind(folderName: kind.folderName) == kind)
	}

	@Test("An unknown folder is no kind")
	func unknownFolderIsNoKind() {
		#expect(TranscriptKind(folderName: "Elsewhere") == nil)
	}
}
