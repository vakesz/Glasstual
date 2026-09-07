/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Darwin
import Foundation
@testable import Glasstual
import Testing

actor RecordingFileLogSink: FileLogSinking {
	private(set) var operations: [FileLogOperation] = []
	private let blocksFirstWrite: Bool
	private let firstWriteResult: FileLogResult
	private var writeCount = 0
	private var blockedWrite: CheckedContinuation<Void, Never>?
	private var waitingForWrite: CheckedContinuation<Void, Never>?

	init(blocksFirstWrite: Bool = false, firstWriteResult: FileLogResult = FileLogResult()) {
		self.blocksFirstWrite = blocksFirstWrite
		self.firstWriteResult = firstWriteResult
	}

	func process(_ operation: FileLogOperation) async -> FileLogResult {
		operations.append(operation)
		if case .write = operation {
			writeCount += 1
			if writeCount == 1 {
				if blocksFirstWrite {
					await withCheckedContinuation { continuation in
						blockedWrite = continuation
						waitingForWrite?.resume()
						waitingForWrite = nil
					}
				}
				return firstWriteResult
			}
		}
		return FileLogResult()
	}

	func waitUntilWriteBlocks() async {
		if blockedWrite != nil {
			return
		}
		await withCheckedContinuation { waitingForWrite = $0 }
	}

	func releaseWrite() {
		blockedWrite?.resume()
		blockedWrite = nil
	}
}

@MainActor
@Suite("Transcript logger ordered I/O", .timeLimit(.minutes(1)))
struct FileLoggerIdleSweepTests {
	@Test("A blocked write leaves MainActor responsive and cannot be overtaken by flush or shutdown")
	func blockedWriteKeepsOrder() async {
		let sink = RecordingFileLogSink(blocksFirstWrite: true)
		let commands = FileLogCommands(sink: sink)
		let destination = FileLogDestination(
			folder: .directory(URL(fileURLWithPath: "/unused")),
			relativePath: "Console"
		)
		let identifier = UUID()
		let date = Date()
		let first = FileLogOperation.write(identifier, destination, date, "begin")
		commands.submit(first)
		await sink.waitUntilWriteBlocks()
		await expectMainActor()

		let remaining: [FileLogOperation] = [
			.write(identifier, destination, date, "body"),
			.reopen(identifier, destination, date.addingTimeInterval(86400)),
			.write(identifier, destination, date.addingTimeInterval(86400), "end"),
			.close(identifier),
			.sweep(date),
			.flush,
		]
		for operation in remaining {
			#expect(commands.submit(operation))
		}
		let (finished, completion) = AsyncStream<Bool>.makeStream()
		commands.finish { completion.yield($0); completion.finish() }
		#expect(!commands.submit(.write(identifier, destination, date, "too late")))
		#expect(await sink.operations == [first])
		await sink.releaseWrite()
		for await succeeded in finished {
			#expect(succeeded)
		}
		#expect(await sink.operations == [first] + remaining + [.shutdown])
	}

	@Test("A failed write is reported by flush and drain without dropping later accepted commands")
	func failuresReachBarriers() async {
		let sink = RecordingFileLogSink(firstWriteResult: FileLogResult(succeeded: false, outOfSpace: true))
		var alerts = 0
		let commands = FileLogCommands(sink: sink, reportNoSpace: { alerts += 1 })
		let destination = FileLogDestination(
			folder: .directory(URL(fileURLWithPath: "/unused")),
			relativePath: "Console"
		)
		let identifier = UUID()
		commands.submit(.write(identifier, destination, Date(), "failed"))
		commands.submit(.close(identifier))
		commands.submit(.write(identifier, destination, Date(), "retry"))
		#expect(await commands.flush() == false)
		#expect(alerts == 1)
		let drained = await withCheckedContinuation { continuation in
			commands.finish { continuation.resume(returning: $0) }
		}
		#expect(!drained)
		#expect(await sink.operations.count == 5)
	}

	@Test(
		"Idle sweep closes only after the limit, and subsequent writes reopen the path",
		arguments: [0, 1199, 1200, 1201, 10000], [false, true]
	)
	func idleLimitBoundary(secondsSinceWrite: Int, written: Bool) async throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		defer { try? FileManager.default.removeItem(at: directory) }
		let commands = FileLogCommands()
		let destination = FileLogDestination(folder: .directory(directory), relativePath: "Console")
		let identifier = UUID()
		let date = try #require(Calendar(identifier: .gregorian).date(from: DateComponents(
			year: 2026,
			month: 9,
			day: 6,
			hour: 12
		)))
		if written {
			commands.submit(.write(identifier, destination, date, "before"))
		} else {
			commands.submit(.reopen(identifier, destination, date))
		}
		#expect(await commands.flush())
		let folder = directory.appendingPathComponent("Console")
		let file = try #require(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
			.first)
		let moved = directory.appendingPathComponent("old.txt")
		try FileManager.default.moveItem(at: file, to: moved)
		let now = date.addingTimeInterval(TimeInterval(secondsSinceWrite))
		commands.submit(.sweep(now))
		commands.submit(.write(identifier, destination, now, "after"))
		let drained = await withCheckedContinuation { continuation in
			commands.finish { continuation.resume(returning: $0) }
		}
		#expect(drained)
		if written, secondsSinceWrite > 1200 {
			#expect(try String(contentsOf: moved, encoding: .utf8) == "before\n")
			#expect(try String(contentsOf: file, encoding: .utf8) == "after\n")
		} else {
			#expect(try String(contentsOf: moved, encoding: .utf8) == (written ? "before\nafter\n" : "after\n"))
			#expect(!FileManager.default.fileExists(atPath: file.path))
		}
	}

	@Test("Rotation uses the accepted date and destination, and close/recreate appends without truncation")
	func rotationAndRecreation() async throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		defer { try? FileManager.default.removeItem(at: directory) }
		let commands = FileLogCommands()
		let destination = FileLogDestination(folder: .directory(directory), relativePath: "/Console/")
		let changed = FileLogDestination(folder: .directory(directory), relativePath: "/Renamed/")
		let identifier = UUID()
		let date = try #require(Calendar(identifier: .gregorian).date(from: DateComponents(
			year: 2026,
			month: 9,
			day: 6,
			hour: 12
		)))
		commands.submit(.write(identifier, destination, date, "begin"))
		commands.submit(.write(identifier, destination, date.addingTimeInterval(86400), "next day"))
		commands.submit(.reopen(identifier, changed, date.addingTimeInterval(86400)))
		commands.submit(.write(identifier, changed, date.addingTimeInterval(86400), "renamed"))
		commands.submit(.close(identifier))
		commands.submit(.write(UUID(), changed, date.addingTimeInterval(86400), "end"))
		let drained = await withCheckedContinuation { continuation in
			commands.finish { continuation.resume(returning: $0) }
		}
		#expect(drained)
		#expect(try String(contentsOf: directory.appendingPathComponent("Console/2026-09-06.txt"), encoding: .utf8) ==
			"begin\n")
		#expect(try String(contentsOf: directory.appendingPathComponent("Console/2026-09-07.txt"), encoding: .utf8) ==
			"next day\n")
		#expect(try String(contentsOf: directory.appendingPathComponent("Renamed/2026-09-07.txt"), encoding: .utf8) ==
			"renamed\nend\n")
	}

	@Test("Open failure releases the old destination and a later write can recover")
	func openFailureAndRecovery() async throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let blocked = directory.appendingPathComponent("not-a-folder")
		try Data("unchanged".utf8).write(to: blocked)
		let good = FileLogDestination(folder: .directory(directory), relativePath: "Console")
		let bad = FileLogDestination(folder: .directory(blocked), relativePath: "Console")
		let sink = FileLogSink()
		let identifier = UUID()
		let date = Date()
		#expect(await sink.process(.write(identifier, good, date, "before")).succeeded)
		#expect(await sink.process(.write(identifier, bad, date, "lost")).succeeded == false)
		#expect(await sink.process(.write(identifier, good, date, "after")).succeeded)
		#expect(await sink.process(.shutdown).succeeded)
		let file = try #require(FileManager.default.contentsOfDirectory(
			at: directory.appendingPathComponent("Console"), includingPropertiesForKeys: nil
		).first)
		#expect(try String(contentsOf: file, encoding: .utf8) == "before\nafter\n")
		#expect(try String(contentsOf: blocked, encoding: .utf8) == "unchanged")
	}

	@Test("Session banners reach disk before close, and a replacement logger starts a new session")
	func sessionBannersSurviveLoggerRelease() async throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		defer { try? FileManager.default.removeItem(at: directory) }
		let commands = FileLogCommands()
		let destination = FileLogDestination(folder: .directory(directory), relativePath: "Console")
		var preferences = ClientPreferences()
		preferences.logToDiskIsEnabled = true
		let fixture = GLTClientEnvironmentFixture(preferences: preferences)
		let client = GLTTestClient(configDictionary: [:], nicknamePassword: nil, fixture: fixture)
		for body in ["first body", "second body"] {
			client.logFile = FileLogger(client: client, commands: commands, destination: destination)
			var line = LogLine()
			line.messageBody = body
			client.writeToLogFile(line)
			#expect(client.logFileSessionIsOpen)
			client.closeLogFile()
			#expect(!client.logFileSessionIsOpen)
			#expect(client.logFile == nil)
		}
		let drained = await withCheckedContinuation { continuation in
			commands.finish { continuation.resume(returning: $0) }
		}
		#expect(drained)
		let files = try FileManager.default.contentsOfDirectory(
			at: directory.appendingPathComponent("Console"), includingPropertiesForKeys: nil
		)
		let contents = try files.sorted { $0.path < $1.path }.map { try String(contentsOf: $0, encoding: .utf8) }
			.joined()
		let lines = contents.split(separator: "\n")
		#expect(lines.count == 14)
		let markers = lines.filter { $0.hasSuffix(IRCLogStrings.sessionMarker(startsSession: true)) ||
			$0.hasSuffix(IRCLogStrings.sessionMarker(startsSession: false)) || $0.hasSuffix("body")
		}
		let expected = [
			IRCLogStrings.sessionMarker(startsSession: true), "first body",
			IRCLogStrings.sessionMarker(startsSession: false),
			IRCLogStrings.sessionMarker(startsSession: true), "second body",
			IRCLogStrings.sessionMarker(startsSession: false),
		]
		#expect(markers.count == expected.count)
		for (line, suffix) in zip(markers, expected) {
			#expect(line.hasSuffix(suffix))
		}
	}

	@Test("Disk-full classification includes wrapped POSIX errors, but not other write failures")
	func diskFullClassification() {
		let full = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
		let wrapped = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnknown.rawValue,
		                      userInfo: [NSUnderlyingErrorKey: full])
		#expect(FileLogResult.failure(full).outOfSpace)
		#expect(FileLogResult.failure(wrapped).outOfSpace)
		#expect(FileLogResult.failure(CocoaError(.fileWriteOutOfSpace)).outOfSpace)
		#expect(!FileLogResult.failure(CocoaError(.fileWriteNoPermission)).outOfSpace)
		#expect(!FileLogResult.failure(full).succeeded)
	}

	@Test("Disk-full alerts do not stack and remain throttled for five minutes after presentation")
	func diskFullAlertThrottle() {
		var throttle = FileLogAlertThrottle()
		let date = Date()
		let initial = throttle.begin(at: date)
		#expect(initial)
		let stacked = throttle.begin(at: date.addingTimeInterval(600))
		#expect(!stacked)
		throttle.dismiss()
		let beforeFirstInterval = throttle.begin(at: date.addingTimeInterval(299))
		#expect(!beforeFirstInterval)
		let firstInterval = throttle.begin(at: date.addingTimeInterval(300))
		#expect(firstInterval)
		throttle.dismiss()
		let beforeSecondInterval = throttle.begin(at: date.addingTimeInterval(599))
		#expect(!beforeSecondInterval)
		let secondInterval = throttle.begin(at: date.addingTimeInterval(600))
		#expect(secondInterval)
	}
}
