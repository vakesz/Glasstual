// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Transcript log library")
struct TranscriptLogLibraryTests {
	@Test("The index lists connections, conversations by kind and days newest first")
	func indexMirrorsTheFolderLayout() async throws {
		let fixture = try TranscriptLogFixture()
		defer { fixture.remove() }
		try fixture.write("a\n", server: "Libera (1a2b3)", folder: "Channels", name: "#swift", day: "2026-01-02")
		try fixture.write("b\n", server: "Libera (1a2b3)", folder: "Channels", name: "#swift", day: "2026-03-04")
		try fixture.write("c\n", server: "Libera (1a2b3)", folder: "Queries", name: "alice", day: "2026-02-01")
		try fixture.write("d\n", server: "Libera (1a2b3)", folder: "Console", day: "2026-02-02")
		try fixture.write("e\n", server: "Another (ffff0)", folder: "Channels", name: "#a", day: "2026-01-01")

		let servers = await TranscriptLogLibrary(root: fixture.root).index()

		#expect(servers.map(\.folder.name) == ["Another", "Libera"])
		let libera = try #require(servers.last)
		#expect(libera.folder.identifier == "1a2b3")
		#expect(libera.conversations.map(\.kind) == [.console, .channel, .direct])
		let channel = try #require(libera.conversations.first { $0.kind == .channel })
		#expect(channel.name == "#swift")
		#expect(channel.days.map(\.filename) == ["2026-03-04.txt", "2026-01-02.txt"])
	}

	@Test("Files and folders that are not logs are left out")
	func strangersAreIgnored() async throws {
		let fixture = try TranscriptLogFixture()
		defer { fixture.remove() }
		try fixture.write("x\n", server: "Libera (1a2b3)", folder: "Channels", name: "#a", day: "not-a-day")
		try fixture.write("x\n", server: "Libera (1a2b3)", folder: "Elsewhere", name: "#a", day: "2026-01-01")
		try fixture.write("x\n", server: "Empty (00000)", folder: "Channels", name: "#a", day: "readme")

		#expect(await TranscriptLogLibrary(root: fixture.root).index().isEmpty)
	}

	@Test("A symbolic link inside the folder is not followed out of it")
	func symbolicLinksAreNotFollowed() async throws {
		let fixture = try TranscriptLogFixture()
		let outside = try TranscriptLogFixture()
		defer { fixture.remove(); outside.remove() }
		try outside.write("secret\n", server: "Elsewhere (00000)", folder: "Channels", name: "#a", day: "2026-01-01")
		try FileManager.default.createSymbolicLink(
			at: fixture.root.appendingPathComponent("Linked (11111)"),
			withDestinationURL: outside.root.appendingPathComponent("Elsewhere (00000)")
		)

		#expect(await TranscriptLogLibrary(root: fixture.root).index().isEmpty)
	}

	@Test("A small file is read whole, with each line's offset")
	func smallFileIsReadWhole() async throws {
		let fixture = try TranscriptLogFixture()
		defer { fixture.remove() }
		let url = try fixture.write("one\ntwo\r\nthree\n", server: "S (00000)", folder: "Console", day: "2026-01-01")

		let chunk = try await TranscriptLogLibrary(root: fixture.root).readChunk(of: url)

		#expect(chunk.lines.map(\.text) == ["one", "two", "three"])
		#expect(chunk.lines.map(\.id) == [0, 4, 9])
		#expect(chunk.startOffset == 0)
		#expect(chunk.hasEarlier == false)
	}

	/** Every line is exactly one hundred bytes, so a line's offset names its
	 number and a cut in the wrong place shows. */
	@Test("A large file is read from its end on a line boundary, and earlier lines join up")
	func largeFileIsReadFromTheEnd() async throws {
		let fixture = try TranscriptLogFixture()
		defer { fixture.remove() }
		let lineCount = 8000
		let text = (0 ..< lineCount).map { Self.line($0) + "\n" }.joined()
		let url = try fixture.write(text, server: "S (00000)", folder: "Console", day: "2026-01-01")
		let library = TranscriptLogLibrary(root: fixture.root)

		let tail = try await library.readChunk(of: url)

		#expect(tail.hasEarlier)
		#expect(tail.startOffset % 100 == 0)
		#expect(tail.lines.last?.text == Self.line(lineCount - 1))
		#expect(tail.lines.first?.text == Self.line(tail.startOffset / 100))
		#expect(tail.lines.count == lineCount - tail.startOffset / 100)

		let earlier = try await library.readChunk(of: url, before: tail.startOffset)

		#expect(earlier.lines.last?.text == Self.line(tail.startOffset / 100 - 1))
		#expect(earlier.startOffset < tail.startOffset)
		#expect(earlier.startOffset % 100 == 0)
	}

	@Test("Reaching back to an offset reads at least that far")
	func readReachesTheTarget() async throws {
		let fixture = try TranscriptLogFixture()
		defer { fixture.remove() }
		let text = (0 ..< 20000).map { Self.line($0) + "\n" }.joined()
		let url = try fixture.write(text, server: "S (00000)", folder: "Console", day: "2026-01-01")
		let library = TranscriptLogLibrary(root: fixture.root)
		let tail = try await library.readChunk(of: url)

		let reached = try await library.readChunk(of: url, before: tail.startOffset, reachingBack: 100)

		#expect(reached.startOffset == 100)
		#expect(reached.lines.first?.id == reached.startOffset)
	}

	@Test("A search finds lines ignoring case and diacritics, and reports where they start")
	func searchFindsLines() async throws {
		let fixture = try TranscriptLogFixture()
		defer { fixture.remove() }
		let url = try fixture.write(
			"Hello World\nsomething\nhello again\nCAFÉ latte\nlast hello",
			server: "S (00000)",
			folder: "Console",
			day: "2026-01-01"
		)
		let library = TranscriptLogLibrary(root: fixture.root)

		let hello = try await library.search("HELLO", in: url)
		#expect(hello.offsets == [0, 22, 46])
		#expect(hello.isTruncated == false)

		let cafe = try await library.search("cafe", in: url)
		#expect(cafe.offsets == [34])

		#expect(try await library.search("absent", in: url).offsets.isEmpty)
		#expect(try await library.search("", in: url).offsets.isEmpty)
	}

	@Test("A search stops at its limit and says so")
	func searchIsBounded() async throws {
		let fixture = try TranscriptLogFixture()
		defer { fixture.remove() }
		let text = String(repeating: "match\n", count: TranscriptLogLibrary.maximumMatches + 10)
		let url = try fixture.write(text, server: "S (00000)", folder: "Console", day: "2026-01-01")

		let result = try await TranscriptLogLibrary(root: fixture.root).search("match", in: url)

		#expect(result.offsets.count == TranscriptLogLibrary.maximumMatches)
		#expect(result.isTruncated)
	}

	private nonisolated static func line(_ index: Int) -> String { // nonisolated: pure
		let number = String(format: "%06d", index)
		return number + String(repeating: "x", count: 93)
	}
}
