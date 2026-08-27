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

import AppKit
import os

private let scriptExecutionLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "ScriptExecution"
)
private let appleScriptSuite = AEEventClass(0x6173_6372)
private let appleScriptSubroutineEvent = AEEventID(0x7073_6272)
private let appleScriptSubroutineName = AEKeyword(0x736E_616D)

@MainActor
extension IRCClient {
	@objc(outputDescriptionForError:forGlasstualCmdScriptAtPath:inputString:)
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
		let input = inputString.isEmpty ? "(no input)" : inputString
		printDebugInformation(
			IRCDiagnosticStrings.scriptFailure(
				filename: (path as NSString).lastPathComponent,
				input: input,
				description: description
			)
		)
		scriptExecutionLogger.error("\(IRCDiagnosticStrings.scriptFailure(description), privacy: .public)")
	}

	@objc(sendGlasstualCmdScriptResult:toChannel:)
	func sendGlasstualCmdScriptResult(_ result: String, toChannel channelName: String?) {
		let destination: IRCTreeItem? = if let channelName {
			(findChannel(channelName) as AnyObject?) as? IRCTreeItem
		} else {
			(self as AnyObject) as? IRCTreeItem
		}
		guard let destination else {
			scriptExecutionLogger.fault("A script returned a result but its destination no longer exists")
			return
		}
		inputText(result.trimmingCharacters(in: .whitespacesAndNewlines), destination: destination)
	}

	@objc(executeGlasstualCmdScriptInContext:)
	func executeGlasstualCmdScript(inContext context: [String: String]) {
		guard let path = context["path"] else { return }
		let input = context["inputString"] ?? ""
		let target = context["targetChannel"]
		let url = URL(fileURLWithPath: path)
		if path.hasSuffix(ResourceDocumentType.scriptFileExtension) {
			executeAppleScript(at: url, path: path, input: input, target: target)
		} else {
			executeUnixScript(at: url, path: path, input: input, target: target)
		}
	}

	private func executeAppleScript(at url: URL, path: String, input: String, target: String?) {
		let event = scriptAppleEvent(input: input, target: target)
		if path.hasPrefix(PathInfo.applicationResources) {
			var initializationError: NSDictionary?
			guard let script = NSAppleScript(contentsOf: url, error: &initializationError) else { return }
			var executionError: NSDictionary?
			let result = script.executeAppleEvent(event, error: &executionError).stringValue
			guard let result else { return }
			sendGlasstualCmdScriptResult(result, toChannel: target)
			return
		}
		do {
			let task = try NSUserAppleScriptTask(url: url)
			task.execute(withAppleEvent: event) { [weak self] result, error in
				let resultString = result?.stringValue
				let scriptError = error as NSError?
				Task { @MainActor [weak self] in
					guard let self else { return }
					if let scriptError {
						outputDescription(for: scriptError, forGlasstualCmdScriptAtPath: path, inputString: input)
					} else if let resultString {
						sendGlasstualCmdScriptResult(resultString, toChannel: target)
					}
				}
			}
		} catch {
			outputDescription(for: error, forGlasstualCmdScriptAtPath: path, inputString: input)
		}
	}

	private func executeUnixScript(at url: URL, path: String, input: String, target: String?) {
		do {
			let task = try NSUserUnixTask(url: url)
			let pipe = Pipe()
			task.standardOutput = pipe.fileHandleForWriting
			let arguments = [target ?? ""] + input.components(separatedBy: .whitespaces)
			task.execute(withArguments: arguments) { [weak self] error in
				let data = pipe.fileHandleForReading.readDataToEndOfFile()
				Task { @MainActor [weak self] in
					guard let self else { return }
					if let error {
						outputDescription(for: error, forGlasstualCmdScriptAtPath: path, inputString: input)
					} else if let result = String(data: data, encoding: .utf8) {
						sendGlasstualCmdScriptResult(result, toChannel: target)
					}
				}
			}
		} catch {
			outputDescription(for: error, forGlasstualCmdScriptAtPath: path, inputString: input)
		}
	}

	private func scriptAppleEvent(input: String, target: String?) -> NSAppleEventDescriptor {
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
		event.setParam(NSAppleEventDescriptor(string: "glasstualcmd"), forKeyword: appleScriptSubroutineName)
		event.setParam(parameters, forKeyword: AEKeyword(keyDirectObject))
		return event
	}
}
