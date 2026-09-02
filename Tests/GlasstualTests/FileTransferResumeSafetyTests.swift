/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/// An incoming transfer used to read the size of whatever already sat at the
/// offered name and offer to resume from there, before the collision-avoiding
/// rename had run. A peer offering `photo.jpg` could therefore append its data
/// on to an unrelated `photo.jpg` in the download folder — and, when the sizes
/// happened to match, report the transfer complete without a byte arriving.
@Suite("File transfer resume safety")
@MainActor
struct FileTransferResumeSafetyTests {
	@Test("An offered name already in use is never the one written into")
	func anExistingFileIsNotResumedInto() throws {
		let directory = try temporaryDirectory()
		let existing = (directory as NSString).appendingPathComponent("photo.jpg")
		#expect(FileManager.default.createFile(atPath: existing, contents: Data(repeating: 0xAB, count: 512)))

		let transfer = try receiver(filename: "photo.jpg", in: directory)
		transfer.claimDestinationFilename()

		#expect(transfer.filename != "photo.jpg")
		/* Nothing to resume from, so the client offers no RESUME at all. */
		#expect(transfer.currentFilesize == 0)
		let untouched = try #require(FileManager.default.contents(atPath: existing))
		#expect(untouched.count == 512)
	}

	@Test("A destination is claimed once, so a partial download can carry on")
	func aClaimedDestinationIsKept() throws {
		let directory = try temporaryDirectory()
		let transfer = try receiver(filename: "photo.jpg", in: directory)

		transfer.claimDestinationFilename()
		let claimed = transfer.filename
		let claimedPath = try #require(transfer.filePath)
		#expect(FileManager.default.createFile(atPath: claimedPath, contents: Data(count: 128)))

		transfer.claimDestinationFilename()

		#expect(transfer.filename == claimed)
		#expect(transfer.currentFilesize == 128)
	}

	@Test("A resume accept nobody asked for moves nothing")
	func anUnsolicitedResumeAcceptIsIgnored() throws {
		let directory = try temporaryDirectory()
		let transfer = try receiver(filename: "photo.jpg", in: directory)

		transfer.didReceiveResumeAccept(512)

		#expect(transfer.isResume == false)
		#expect(transfer.processedFilesize == 0)
		#expect(transfer.transferStatus == .stopped)
	}

	private func receiver(filename: String, in directory: String) throws -> FileTransferController {
		let transfer = try #require(FileTransferController.receiver(
			for: GLTTestClient(),
			nickname: "alice",
			address: "203.0.113.5",
			port: 1234,
			filename: filename,
			filesize: 2048,
			token: nil
		))
		transfer.path = directory

		return transfer
	}

	private func temporaryDirectory() throws -> String {
		let url = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("GlasstualTransfers-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

		return url.path
	}
}
