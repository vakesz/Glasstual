// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@Suite("User script runner")
@MainActor
struct UserScriptRunnerTests {
	private static let subroutineNameKeyword = AEKeyword(0x736E_616D)

	@Test("Delayed script output cannot target a replacement connection or channel")
	func staleScriptDestination() throws {
		let session = TestServerSession()
		session.isConnected = true
		let channel = try #require(session.findConversationOrCreate("#scripts"))
		let original = ScriptInvocation(session: session, target: channel.name)
		#expect(session.scriptInvocationIsCurrent(original))
		session.cancelPendingSessionTasks()
		session.sendGlasstualCmdScriptResult("/raw PRIVMSG #scripts :old session", to: original)
		#expect(session.sentLines.count == 0)
		let removedChannel = ScriptInvocation(session: session, target: channel.name)
		session.conversationList = []
		_ = try #require(session.findConversationOrCreate("#scripts"))
		session.sendGlasstualCmdScriptResult("/raw PRIVMSG #scripts :old channel", to: removedChannel)
		#expect(session.sentLines.count == 0)
		let current = ScriptInvocation(session: session, target: "#scripts")
		session.sendGlasstualCmdScriptResult("/raw PRIVMSG #scripts :current", to: current)
		#expect(session.sentLines as? [String] == ["PRIVMSG #scripts :current"])
	}

	@Test("The Apple event carries the requested handler name")
	func appleEventCarriesHandlerName() throws {
		let handler = UserScriptRunner.handlerName
		let event = UserScriptRunner.appleEvent(handler: handler, input: "in", target: "#channel")
		let name = try #require(event.paramDescriptor(forKeyword: Self.subroutineNameKeyword)?.stringValue)
		#expect(name == handler)
	}

	@Test("The Apple event passes input and destination as the direct object list")
	func appleEventCarriesArguments() throws {
		let event = UserScriptRunner.appleEvent(
			handler: UserScriptRunner.handlerName,
			input: "hello",
			target: "#glasstual"
		)
		let arguments = try #require(event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)))
		#expect(arguments.numberOfItems == 2)
		#expect(arguments.atIndex(1)?.stringValue == "hello")
		#expect(arguments.atIndex(2)?.stringValue == "#glasstual")
	}

	@Test("A nil destination is passed as an empty string")
	func appleEventUsesEmptyStringForMissingTarget() throws {
		let event = UserScriptRunner.appleEvent(
			handler: UserScriptRunner.handlerName,
			input: "",
			target: nil
		)
		let arguments = try #require(event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)))
		#expect(arguments.atIndex(2)?.stringValue == "")
	}

	@Test("An NSAppleScript error dictionary survives the trip into an NSError")
	func errorDictionaryIsPreserved() {
		let information: NSDictionary = [
			NSAppleScript.errorNumber: -2700,
			NSAppleScript.errorMessage: "boom",
		]
		let error = UserScriptRunner.error(from: information)
		#expect(error.code == -2700)
		#expect(error.userInfo[NSAppleScript.errorMessage] as? String == "boom")
	}

	@Test("A failure with no error number is recorded as the general script error")
	func failureWithoutNumberIsTheGeneralError() {
		let error = UserScriptRunner.error(from: [NSAppleScript.errorMessage: "boom"])

		#expect(error.code == UserScriptRunner.unknownScriptError)
	}

	@Test("Both bundled scripts define the handler Glasstual asks for", arguments: ["date", "moti"])
	func bundledScriptsDefineTheHandler(named name: String) throws {
		let url = try #require(
			Bundle.main.url(forResource: name, withExtension: "scpt", subdirectory: "Bundled Scripts")
				?? Bundle.main.url(forResource: name, withExtension: "scpt")
		)
		let source = try String(
			data: #require(try? Data(contentsOf: url)),
			encoding: .macOSRoman
		)
		// The compiled script stores handler names as plain bytes in its data
		// fork, which is enough to tell the two spellings apart.
		#expect(source?.contains(UserScriptRunner.handlerName) == true)
	}

	@Test("The bundled scripts folder contains only commands the loader can execute")
	func bundledScriptsContainOnlyLoadableCommands() throws {
		let directory = try #require(Bundle.main.resourceURL?.appendingPathComponent("Bundled Scripts"))
		let entries = try FileManager.default.contentsOfDirectory(
			at: directory,
			includingPropertiesForKeys: [.isExecutableKey],
			options: [.skipsHiddenFiles]
		)

		for entry in entries {
			let isScript = entry.pathExtension.caseInsensitiveCompare(
				ResourceDocumentKind.scriptFilenameExtension
			) == .orderedSame
			let isExecutable = try entry.resourceValues(forKeys: [.isExecutableKey]).isExecutable == true
			#expect(isScript || isExecutable, "Unsupported bundled script resource: \(entry.lastPathComponent)")
		}
	}

	/// Writes `data` and closes the handle. Blocking on purpose: a
	/// pipe holds about 64 KB, so this returns only once something else has
	/// drained what it wrote.
	@concurrent
	private static func write(_ data: Data, to handle: FileHandle) async throws {
		defer { try? handle.close() }
		try handle.write(contentsOf: data)
	}

	/// A script's output used to be read only after it had terminated, which
	/// deadlocked any script writing more than the pipe holds: it blocked in
	/// `write(2)`, so it never exited, so the read never started.
	@Test("Output larger than the pipe buffer is drained while the script still runs")
	func outputLargerThanThePipeBufferIsDrained() async throws {
		let pipe = Pipe()
		let byteCount = 512 * 1024
		let expected = Data((0 ..< byteCount).map { UInt8(truncatingIfNeeded: $0) })
		let output = Task { try await UserScriptRunner.readOutput(from: pipe.fileHandleForReading) }

		try await Self.write(expected, to: pipe.fileHandleForWriting)

		let data = try await output.value
		try? pipe.fileHandleForReading.close()

		#expect(data == expected)
	}

	/// Silent pipes must not delay another reader. Cleanup has its own task so
	/// a regression reports an assertion instead of hanging behind the read.
	@Test("Silent script readers do not block independent output", .timeLimit(.minutes(1)))
	func idleReadersLeaveThePoolFree() async throws {
		let idlePipes = (0 ..< 64).map { _ in Pipe() }
		var requiredCleanup = false
		let cleanup = Task {
			do { try await Task.sleep(for: .seconds(10)) } catch { return }
			requiredCleanup = true
			for idle in idlePipes {
				try? idle.fileHandleForWriting.close()
			}
		}
		defer {
			cleanup.cancel()
			for idle in idlePipes {
				try? idle.fileHandleForWriting.close()
				try? idle.fileHandleForReading.close()
			}
		}

		try await withThrowingTaskGroup(of: Data.self) { group in
			for idle in idlePipes {
				group.addTask { try await UserScriptRunner.readOutput(from: idle.fileHandleForReading) }
			}

			let pipe = Pipe()
			let output = Task { try await UserScriptRunner.readOutput(from: pipe.fileHandleForReading) }
			try await Self.write(Data(repeating: 0x41, count: 16), to: pipe.fileHandleForWriting)

			#expect(try await output.value.count == 16)
			#expect(requiredCleanup == false, "The completed reader waited for silent pipes to close")
			try? pipe.fileHandleForReading.close()

			for idle in idlePipes {
				try? idle.fileHandleForWriting.close()
			}
			for try await data in group {
				#expect(data.isEmpty)
			}
		}
	}

	@Test("Cancelling an idle reader completes without waiting for its writer", .timeLimit(.minutes(1)))
	func cancellationStopsIdleRead() async {
		let pipe = Pipe()
		var requiredWriterClosure = false
		let cleanup = Task {
			do { try await Task.sleep(for: .seconds(10)) } catch { return }
			requiredWriterClosure = true
			try? pipe.fileHandleForWriting.close()
		}
		defer {
			cleanup.cancel()
			try? pipe.fileHandleForReading.close()
			try? pipe.fileHandleForWriting.close()
		}
		let output = Task { try await UserScriptRunner.readOutput(from: pipe.fileHandleForReading) }
		// Cancellation before the reader starts only tests its initial guard.
		// Wait for the native readiness bridge so the suspended stream and its
		// handler teardown are both exercised, with a deadline for regressions.
		let deadline = ContinuousClock.now.advanced(by: .seconds(5))
		while pipe.fileHandleForReading.readabilityHandler == nil,
		      ContinuousClock.now < deadline, !Task.isCancelled
		{
			await Task.yield()
		}
		#expect(pipe.fileHandleForReading.readabilityHandler != nil)
		output.cancel()
		await #expect(throws: CancellationError.self) { try await output.value }
		#expect(requiredWriterClosure == false, "Cancellation waited for the writer to close")
		#expect(pipe.fileHandleForReading.readabilityHandler == nil)
	}

	@Test("Oversized output is drained but rejected, never returned as partial commands")
	func outputPastTheCeilingIsRejected() async throws {
		let pipe = Pipe()
		let byteCount = UserScriptRunner.maximumOutputBytes + (128 * 1024)
		let output = Task { try await UserScriptRunner.readOutput(from: pipe.fileHandleForReading) }

		try await Self.write(Data(repeating: 0x41, count: byteCount), to: pipe.fileHandleForWriting)

		let result = await output.result
		try? pipe.fileHandleForReading.close()

		#expect(throws: UserScriptRunner.OutputError.tooLarge) { try result.get() }
	}

	@Test("Invalid UTF-8 is an error, including a valid command followed by a truncated scalar")
	func invalidEncodingRejectsTheWholeOutput() {
		let data = Data("/join #must-not-run\n".utf8) + Data([0xF0, 0x9F])
		#expect(throws: UserScriptRunner.OutputError.invalidUTF8) {
			try UserScriptRunner.decodedOutput(data)
		}
	}

	@Test("Empty output and exactly the output ceiling remain valid")
	func validOutputBoundaries() throws {
		#expect(try UserScriptRunner.decodedOutput(Data()) == "")
		let data = Data(repeating: 0x41, count: UserScriptRunner.maximumOutputBytes)
		#expect(try UserScriptRunner.decodedOutput(data).utf8.count == data.count)
	}

	@Test("A valid write-only pipe handle is rejected before installing a reader")
	func outputReadFailureIsReported() async throws {
		let pipe = Pipe()
		defer {
			try? pipe.fileHandleForReading.close()
			try? pipe.fileHandleForWriting.close()
		}
		await #expect(throws: POSIXError(.EBADF)) {
			try await UserScriptRunner.readOutput(from: pipe.fileHandleForWriting)
		}
	}
}
