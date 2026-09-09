/* *********************************************************************
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *********************************************************************** */

import Foundation
import os

private let scriptExecutionLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "ScriptExecution"
)
private let appleScriptSuite = AEEventClass(0x6173_6372)
private let appleScriptSubroutineEvent = AEEventID(0x7073_6272)
private let appleScriptSubroutineName = AEKeyword(0x736E_616D)

/// Helpers for the `glasstualcmd` script bridge, kept free of `IRCClient` so
/// they can be exercised without a live client.
enum ScriptExecutionSupport {
	nonisolated enum OutputError: LocalizedError, Equatable { // nonisolated: value
		case tooLarge
		case invalidUTF8
		case unavailableScript

		var errorDescription: String? {
			switch self {
			case .tooLarge: String(localized: .Plugins.scriptOutputTooLarge)
			case .invalidUTF8: String(localized: .Plugins.scriptOutputInvalidEncoding)
			case .unavailableScript: String(localized: .Plugins.scriptUnavailable)
			}
		}
	}

	/// The handler name Glasstual asks a script to run.
	static let handlerName = "glasstualcmd"

	/// The handler name Textual used. Scripts written for Textual — including
	/// every user script carried over from it — still define this one, so it is
	/// tried when the preferred name is not defined.
	static let legacyHandlerName = "textualcmd"

	/// `errAEEventNotHandled`: the script has no handler under that name.
	static let handlerNotDefinedError = -1708

	/** How much of a script's output is kept.

	 Everything past it is read and dropped: the pipe still has to be drained so
	 the script can finish, but a runaway script must not grow the buffer
	 without bound. The same ceiling bounds the decoded text and the result a
	 script hands back, because an AppleScript result never passes through the
	 reader at all. */
	nonisolated static let maximumOutputBytes = 1 << 20 // nonisolated: let

	private nonisolated static let outputChunkBytes = 64 * 1024 // nonisolated: let

	/// Reads `handle` to end of file, keeping at most ``maximumOutputBytes``.
	///
	/// This runs while the script is still executing. A pipe holds a fixed
	/// amount (64 KB on macOS); a script that writes more blocks in `write(2)`
	/// until something reads, so a reader that waits for termination first
	/// would wedge the script and never start.
	@concurrent
	static func readOutput(from handle: FileHandle) async throws -> Data {
		var accumulated = Data()
		var exceededLimit = false

		while true {
			guard let chunk = try handle.read(upToCount: outputChunkBytes), chunk.isEmpty == false else {
				break
			}

			let remaining = maximumOutputBytes - accumulated.count
			exceededLimit = exceededLimit || chunk.count > remaining

			if remaining > 0 {
				accumulated.append(chunk.prefix(remaining))
			}
		}

		guard exceededLimit == false else { throw OutputError.tooLarge }
		return accumulated
	}

	nonisolated static func decodedOutput(_ data: Data) throws -> String { // nonisolated: pure
		guard data.count <= maximumOutputBytes else { throw OutputError.tooLarge }
		guard let output = String(data: data, encoding: .utf8) else { throw OutputError.invalidUTF8 }
		return output
	}

	static func appleEvent(handler: String, input: String, target: String?) -> NSAppleEventDescriptor {
		let parameters = NSAppleEventDescriptor.list()
		parameters.insert(NSAppleEventDescriptor(string: input), at: 1)
		parameters.insert(NSAppleEventDescriptor(string: target ?? ""), at: 2)
		let event = NSAppleEventDescriptor(
			eventClass: appleScriptSuite,
			eventID: appleScriptSubroutineEvent,
			targetDescriptor: NSAppleEventDescriptor(processIdentifier: getpid()),
			returnID: AEReturnID(kAutoGenerateReturnID),
			transactionID: AETransactionID(kAnyTransactionID)
		)
		event.setParam(NSAppleEventDescriptor(string: handler), forKeyword: appleScriptSubroutineName)
		event.setParam(parameters, forKeyword: AEKeyword(keyDirectObject))
		return event
	}

	/// `true` when the script simply does not define the handler that was asked
	/// for, which is the only failure worth retrying under the legacy name.
	static func isHandlerNotDefined(_ error: NSError) -> Bool {
		if let number = error.userInfo[NSAppleScript.errorNumber] as? Int {
			return number == handlerNotDefinedError
		}
		return error.code == handlerNotDefinedError
	}

	/// Turns the `NSDictionary` that `NSAppleScript` reports failures through
	/// into an `Error` the shared reporting path understands.
	static func error(from information: NSDictionary?) -> NSError {
		let userInfo = (information as? [String: Any]) ?? [:]
		let code = (userInfo[NSAppleScript.errorNumber] as? Int) ?? handlerNotDefinedError
		return NSError(domain: NSOSStatusErrorDomain, code: code, userInfo: userInfo)
	}
}

/// The destination is fixed when execution starts. A reused channel name or a
/// reconnected server is a different destination for delayed script output.
@MainActor
final class ScriptInvocation {
	let sessionIdentifier: UUID
	let connectionIdentifier: String?
	let targetName: String?
	weak var channel: IRCChannel?

	init(client: IRCClient, target: String?) {
		sessionIdentifier = client.startup.identifier
		connectionIdentifier = client.socket?.uniqueIdentifier
		targetName = target
		channel = target.flatMap(client.findChannel)
	}
}

@MainActor
extension IRCClient {
	func outputDescription(
		for error: Error,
		forGlasstualCmdScriptAtPath path: String,
		inputString: String
	) {
		let nsError = error as NSError
		let description = (nsError.userInfo[NSAppleScript.errorMessage] as? String)
			?? (nsError.userInfo[NSAppleScript.errorBriefMessage] as? String)
			?? nsError.localizedFailureReason
			?? nsError.localizedDescription
		let input = inputString.isEmpty ? String(localized: .Plugins.scriptNoInput) : inputString
		printDebugInformation(
			IRCDiagnosticStrings.scriptFailure(
				filename: URL(fileURLWithPath: path).lastPathComponent,
				input: input,
				description: description
			)
		)
		scriptExecutionLogger.error("\(IRCDiagnosticStrings.scriptFailure(description), privacy: .public)")
	}

	func scriptInvocationIsCurrent(_ invocation: ScriptInvocation) -> Bool {
		guard !isTerminating, !isQuitting, !isDisconnecting,
		      startup.identifier == invocation.sessionIdentifier,
		      socket?.uniqueIdentifier == invocation.connectionIdentifier else { return false }
		guard invocation.targetName != nil else { return true }
		return invocation.channel.map { channel in channelList.contains { $0 === channel } } ?? false
	}

	func sendGlasstualCmdScriptResult(_ result: String, to invocation: ScriptInvocation) {
		guard scriptInvocationIsCurrent(invocation) else { return }
		guard result.utf8.count <= ScriptExecutionSupport.maximumOutputBytes else {
			printDebugInformation(String(localized: .Plugins.scriptOutputTooLarge))
			return
		}
		inputText(result.trimmingCharacters(in: .whitespacesAndNewlines), destination: invocation.channel ?? self)
	}

	func sendGlasstualCmdScriptResult(_ result: String, toChannel channelName: String?) {
		sendGlasstualCmdScriptResult(result, to: ScriptInvocation(client: self, target: channelName))
	}

	func executeGlasstualCmdScript(inContext context: [String: String]) {
		guard let path = context["path"] else { return }
		let input = context["inputString"] ?? ""
		let target = context["targetChannel"]
		let invocation = ScriptInvocation(client: self, target: target)
		guard scriptInvocationIsCurrent(invocation) else { return }
		let url = URL(fileURLWithPath: path)
		guard let script = SharedApplication.sharedPluginManager().script(at: url) else {
			outputDescription(
				for: ScriptExecutionSupport.OutputError.unavailableScript,
				forGlasstualCmdScriptAtPath: path,
				inputString: input
			)
			return
		}
		switch script.kind {
		case .appleScript:
			executeAppleScript(script, input: input, target: target, invocation: invocation)
		case .unixExecutable:
			executeUnixScript(at: url, path: path, input: input, target: target, invocation: invocation)
		}
	}

	private func executeAppleScript(
		_ script: PluginScript,
		input: String,
		target: String?,
		invocation: ScriptInvocation
	) {
		switch script.origin {
		case .bundled:
			executeBundledAppleScript(
				at: script.url,
				path: script.url.path,
				input: input,
				target: target,
				invocation: invocation
			)
		case .custom:
			executeUserAppleScript(
				at: script.url,
				path: script.url.path,
				input: input,
				target: target,
				handler: ScriptExecutionSupport.handlerName,
				invocation: invocation
			)
		}
	}

	private func executeBundledAppleScript(
		at url: URL,
		path: String,
		input: String,
		target: String?,
		invocation: ScriptInvocation
	) {
		var initializationError: NSDictionary?
		guard let script = NSAppleScript(contentsOf: url, error: &initializationError) else {
			outputDescription(
				for: ScriptExecutionSupport.error(from: initializationError),
				forGlasstualCmdScriptAtPath: path,
				inputString: input
			)
			return
		}
		let handlers = [ScriptExecutionSupport.handlerName, ScriptExecutionSupport.legacyHandlerName]
		for (index, handler) in handlers.enumerated() {
			var executionError: NSDictionary?
			let event = ScriptExecutionSupport.appleEvent(handler: handler, input: input, target: target)
			let result = script.executeAppleEvent(event, error: &executionError)
			guard let executionError else {
				if let resultString = result.stringValue {
					sendGlasstualCmdScriptResult(resultString, to: invocation)
				}
				return
			}
			let error = ScriptExecutionSupport.error(from: executionError)
			if index < handlers.count - 1, ScriptExecutionSupport.isHandlerNotDefined(error) {
				continue
			}
			outputDescription(for: error, forGlasstualCmdScriptAtPath: path, inputString: input)
			return
		}
	}

	private func executeUserAppleScript(
		at url: URL,
		path: String,
		input: String,
		target: String?,
		handler: String,
		invocation: ScriptInvocation
	) {
		do {
			let task = try NSUserAppleScriptTask(url: url)
			let event = ScriptExecutionSupport.appleEvent(handler: handler, input: input, target: target)
			task.execute(withAppleEvent: event) { [weak self] result, error in
				let resultString = result?.stringValue
				let scriptError = error as NSError?
				Task { @MainActor [weak self] in
					guard let self, scriptInvocationIsCurrent(invocation) else { return }
					guard let scriptError else {
						if let resultString {
							sendGlasstualCmdScriptResult(resultString, to: invocation)
						}
						return
					}
					if handler == ScriptExecutionSupport.handlerName,
					   ScriptExecutionSupport.isHandlerNotDefined(scriptError)
					{
						executeUserAppleScript(
							at: url,
							path: path,
							input: input,
							target: target,
							handler: ScriptExecutionSupport.legacyHandlerName,
							invocation: invocation
						)
						return
					}
					outputDescription(for: scriptError, forGlasstualCmdScriptAtPath: path, inputString: input)
				}
			}
		} catch {
			outputDescription(for: error, forGlasstualCmdScriptAtPath: path, inputString: input)
		}
	}

	private func executeUnixScript(
		at url: URL,
		path: String,
		input: String,
		target: String?,
		invocation: ScriptInvocation
	) {
		do {
			let task = try NSUserUnixTask(url: url)
			let pipe = Pipe()
			task.standardOutput = pipe.fileHandleForWriting
			let arguments = [target ?? ""] + input.components(separatedBy: .whitespaces)
			let readHandle = pipe.fileHandleForReading
			let writeHandle = pipe.fileHandleForWriting
			// Start draining before the script runs. Reading only once it has
			// terminated deadlocks a script whose output overflows the pipe.
			let output = Task { try await ScriptExecutionSupport.readOutput(from: readHandle) }
			task.execute(withArguments: arguments) { [weak self] error in
				// The task holds the only other reference to the write end; closing
				// it here is what lets the drain above see EOF instead of blocking.
				try? writeHandle.close()
				Task { @MainActor [weak self] in
					let result = await output.result
					try? readHandle.close()
					guard let self, scriptInvocationIsCurrent(invocation) else { return }
					do {
						if let error {
							throw error
						}
						let text = try ScriptExecutionSupport.decodedOutput(result.get())
						sendGlasstualCmdScriptResult(text, to: invocation)
					} catch {
						outputDescription(for: error, forGlasstualCmdScriptAtPath: path, inputString: input)
					}
				}
			}
		} catch {
			outputDescription(for: error, forGlasstualCmdScriptAtPath: path, inputString: input)
		}
	}
}
