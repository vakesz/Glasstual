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
@testable import Glasstual
import Testing

@Suite("Script execution support")
@MainActor
struct ScriptExecutionSupportTests {
	private static let subroutineNameKeyword = AEKeyword(0x736E_616D)

	@Test("Delayed script output cannot target a replacement connection or channel")
	func staleScriptDestination() throws {
		let client = GLTTestClient()
		client.isConnected = true
		let channel = try #require(client.findChannelOrCreate("#scripts"))
		let original = ScriptInvocation(client: client, target: channel.name)
		#expect(client.scriptInvocationIsCurrent(original))
		client.cancelPendingSessionTasks()
		client.sendGlasstualCmdScriptResult("/raw PRIVMSG #scripts :old session", to: original)
		#expect(client.sentLines.count == 0)
		let removedChannel = ScriptInvocation(client: client, target: channel.name)
		client.channelList = []
		_ = try #require(client.findChannelOrCreate("#scripts"))
		client.sendGlasstualCmdScriptResult("/raw PRIVMSG #scripts :old channel", to: removedChannel)
		#expect(client.sentLines.count == 0)
		let current = ScriptInvocation(client: client, target: "#scripts")
		client.sendGlasstualCmdScriptResult("/raw PRIVMSG #scripts :current", to: current)
		#expect(client.sentLines as? [String] == ["PRIVMSG #scripts :current"])
	}

	@Test("The Apple event carries the requested handler name")
	func appleEventCarriesHandlerName() throws {
		for handler in [ScriptExecutionSupport.handlerName, ScriptExecutionSupport.legacyHandlerName] {
			let event = ScriptExecutionSupport.appleEvent(handler: handler, input: "in", target: "#channel")
			let name = try #require(event.paramDescriptor(forKeyword: Self.subroutineNameKeyword)?.stringValue)
			#expect(name == handler)
		}
	}

	@Test("The Apple event passes input and destination as the direct object list")
	func appleEventCarriesArguments() throws {
		let event = ScriptExecutionSupport.appleEvent(
			handler: ScriptExecutionSupport.handlerName,
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
		let event = ScriptExecutionSupport.appleEvent(
			handler: ScriptExecutionSupport.handlerName,
			input: "",
			target: nil
		)
		let arguments = try #require(event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)))
		#expect(arguments.atIndex(2)?.stringValue == "")
	}

	@Test("errAEEventNotHandled is recognised, whether it arrives in userInfo or as the code")
	func recognisesHandlerNotDefined() {
		let fromUserInfo = NSError(
			domain: NSOSStatusErrorDomain,
			code: 1,
			userInfo: [NSAppleScript.errorNumber: ScriptExecutionSupport.handlerNotDefinedError]
		)
		#expect(ScriptExecutionSupport.isHandlerNotDefined(fromUserInfo))

		let fromCode = NSError(
			domain: NSOSStatusErrorDomain,
			code: ScriptExecutionSupport.handlerNotDefinedError,
			userInfo: [:]
		)
		#expect(ScriptExecutionSupport.isHandlerNotDefined(fromCode))
	}

	@Test("Other AppleScript failures are not treated as a missing handler")
	func otherFailuresAreNotHandlerNotDefined() {
		let error = NSError(
			domain: NSOSStatusErrorDomain,
			code: 1,
			userInfo: [NSAppleScript.errorNumber: -2700, NSAppleScript.errorMessage: "boom"]
		)
		#expect(ScriptExecutionSupport.isHandlerNotDefined(error) == false)
	}

	@Test("An NSAppleScript error dictionary survives the trip into an NSError")
	func errorDictionaryIsPreserved() {
		let information: NSDictionary = [
			NSAppleScript.errorNumber: -2700,
			NSAppleScript.errorMessage: "boom",
		]
		let error = ScriptExecutionSupport.error(from: information)
		#expect(error.code == -2700)
		#expect(error.userInfo[NSAppleScript.errorMessage] as? String == "boom")
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
		#expect(source?.contains(ScriptExecutionSupport.handlerName) == true)
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
				ResourceDocumentType.scriptFilenameExtension
			) == .orderedSame
			let isExecutable = try entry.resourceValues(forKeys: [.isExecutableKey]).isExecutable == true
			#expect(isScript || isExecutable, "Unsupported bundled script resource: \(entry.lastPathComponent)")
		}
	}

	/// Writes `byteCount` bytes and closes the handle. Blocking on purpose: a
	/// pipe holds about 64 KB, so this returns only once something else has
	/// drained what it wrote.
	@concurrent
	private static func write(byteCount: Int, to handle: FileHandle) async {
		try? handle.write(contentsOf: Data(repeating: 0x41, count: byteCount))
		try? handle.close()
	}

	/// A script's output used to be read only after it had terminated, which
	/// deadlocked any script writing more than the pipe holds: it blocked in
	/// `write(2)`, so it never exited, so the read never started.
	@Test("Output larger than the pipe buffer is drained while the script still runs")
	func outputLargerThanThePipeBufferIsDrained() async throws {
		let pipe = Pipe()
		let byteCount = 512 * 1024
		let output = Task { try await ScriptExecutionSupport.readOutput(from: pipe.fileHandleForReading) }

		await Self.write(byteCount: byteCount, to: pipe.fileHandleForWriting)

		let data = try await output.value
		try? pipe.fileHandleForReading.close()

		#expect(data.count == byteCount)
	}

	@Test("Oversized output is drained but rejected, never returned as partial commands")
	func outputPastTheCeilingIsRejected() async {
		let pipe = Pipe()
		let byteCount = ScriptExecutionSupport.maximumOutputBytes + (128 * 1024)
		let output = Task { try await ScriptExecutionSupport.readOutput(from: pipe.fileHandleForReading) }

		await Self.write(byteCount: byteCount, to: pipe.fileHandleForWriting)

		let result = await output.result
		try? pipe.fileHandleForReading.close()

		#expect(throws: ScriptExecutionSupport.OutputError.tooLarge) { try result.get() }
	}

	@Test("Invalid UTF-8 is an error, including a valid command followed by a truncated scalar")
	func invalidEncodingRejectsTheWholeOutput() {
		let data = Data("/join #must-not-run\n".utf8) + Data([0xF0, 0x9F])
		#expect(throws: ScriptExecutionSupport.OutputError.invalidUTF8) {
			try ScriptExecutionSupport.decodedOutput(data)
		}
	}

	@Test("Empty output and exactly the output ceiling remain valid")
	func validOutputBoundaries() throws {
		#expect(try ScriptExecutionSupport.decodedOutput(Data()) == "")
		let data = Data(repeating: 0x41, count: ScriptExecutionSupport.maximumOutputBytes)
		#expect(try ScriptExecutionSupport.decodedOutput(data).utf8.count == data.count)
	}

	@Test("A read failure is propagated instead of returning the bytes read so far")
	func outputReadFailureIsReported() async throws {
		let pipe = Pipe()
		try pipe.fileHandleForReading.close()
		try pipe.fileHandleForWriting.close()
		await #expect(throws: (any Error).self) {
			try await ScriptExecutionSupport.readOutput(from: pipe.fileHandleForReading)
		}
	}
}
