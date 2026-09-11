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
		defer { try? FileManager.default.removeItem(atPath: directory) }
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
	func aClaimedDestinationIsKept() async throws {
		let directory = try temporaryDirectory()
		defer { try? FileManager.default.removeItem(atPath: directory) }
		let transfer = try receiver(filename: "photo.jpg", in: directory)

		transfer.claimDestinationFilename()
		let claimed = transfer.filename
		let file = try #require(transfer.ownedFile)
		try await file.write(Data(count: 128), at: 0)

		transfer.claimDestinationFilename()

		#expect(transfer.filename == claimed)
		#expect(transfer.currentFilesize == 128)
		#expect(try await file.size() == 128)
		#expect(transfer.wireFilename == "photo.jpg")
	}

	@Test("A resume accept nobody asked for moves nothing")
	func anUnsolicitedResumeAcceptIsIgnored() throws {
		let directory = try temporaryDirectory()
		defer { try? FileManager.default.removeItem(atPath: directory) }
		let transfer = try receiver(filename: "photo.jpg", in: directory)

		transfer.didReceiveResumeAccept(512)

		#expect(transfer.isResume == false)
		#expect(transfer.processedFilesize == 0)
		#expect(transfer.transferStatus == .stopped)
	}

	/** The RESUME timeout used to close the transfer on whatever it found when it
	 woke, and a `DCC ACCEPT` that arrived during the wait leaves the transfer
	 connecting rather than waiting: the sleep then killed a download that had
	 just begun. The wait fails only the session it was started for, and only
	 while that session is still waiting. */
	@Test("A RESUME timeout that fires after the accept arrived closes nothing")
	func aResumeTimeoutAfterTheAcceptIsIgnored() throws {
		let directory = try temporaryDirectory()
		defer { try? FileManager.default.removeItem(atPath: directory) }
		let transfer = try receiver(filename: "photo.jpg", in: directory)
		/* Where `didReceiveResumeAccept` leaves the transfer: the wait is over
		 and the connection it asked for is being made. */
		transfer.transferStatus = .connecting

		#expect(transfer.resumeTimeoutExpired(for: transfer.sessionID) == false)
		#expect(transfer.transferStatus == .connecting)
		#expect(transfer.errorMessageDescription == nil)
	}

	@Test("A RESUME timeout belonging to an earlier session closes nothing")
	func aResumeTimeoutFromAnEarlierSessionIsIgnored() throws {
		let directory = try temporaryDirectory()
		defer { try? FileManager.default.removeItem(atPath: directory) }
		let transfer = try receiver(filename: "photo.jpg", in: directory)
		transfer.transferStatus = .waitingForResumeAccept

		#expect(transfer.resumeTimeoutExpired(for: UUID()) == false)
		#expect(transfer.transferStatus == .waitingForResumeAccept)
		#expect(transfer.errorMessageDescription == nil)
	}

	@Test("A RESUME the peer never answered fails its own session")
	func anUnansweredResumeTimesOut() throws {
		let directory = try temporaryDirectory()
		defer { try? FileManager.default.removeItem(atPath: directory) }
		let transfer = try receiver(filename: "photo.jpg", in: directory)
		transfer.transferStatus = .waitingForResumeAccept

		#expect(transfer.resumeTimeoutExpired(for: transfer.sessionID))
		#expect(transfer.transferStatus == .recoverableError)
		#expect(transfer.errorMessageDescription != nil)
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
