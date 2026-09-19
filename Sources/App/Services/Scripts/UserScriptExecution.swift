// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import os

private let scriptExecutionLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "UserScriptExecution"
)

/// The destination is fixed when execution starts. A reused conversation name
/// or a reconnected server is a different destination for delayed script output.
@MainActor
final class ScriptInvocation {
	let sessionIdentifier: UUID
	let connectionIdentifier: String?
	let targetName: String?
	weak var conversation: Conversation?

	init(session: ServerSession, target: String?) {
		sessionIdentifier = session.startup.identifier
		connectionIdentifier = session.socket?.uniqueIdentifier
		targetName = target
		conversation = target.flatMap(session.findConversation)
	}
}

@MainActor
extension ServerSession {
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
		let input = inputString.isEmpty ? String(localized: .Scripts.scriptNoInput) : inputString
		printDebugInformation(
			String(localized: .IRC.scriptExecutionFailure(URL(fileURLWithPath: path).lastPathComponent, input, description))
		)
		scriptExecutionLogger.error("\(String(localized: .IRC.scriptErrorsExecutionFailure(description)), privacy: .public)")
	}

	func scriptInvocationIsCurrent(_ invocation: ScriptInvocation) -> Bool {
		guard !isTerminating, !isQuitting, !isDisconnecting,
		      startup.identifier == invocation.sessionIdentifier,
		      socket?.uniqueIdentifier == invocation.connectionIdentifier else { return false }
		guard invocation.targetName != nil else { return true }
		return invocation.conversation.map { conversation in
			conversationList.contains { $0 === conversation }
		} ?? false
	}

	func sendGlasstualCmdScriptResult(_ result: String, to invocation: ScriptInvocation) {
		guard scriptInvocationIsCurrent(invocation) else { return }
		guard result.utf8.count <= UserScriptRunner.maximumOutputBytes else {
			printDebugInformation(String(localized: .Scripts.scriptOutputTooLarge))
			return
		}
		inputText(result.trimmingCharacters(in: .whitespacesAndNewlines), destination: invocation.conversation ?? self)
	}

	/// Runs `script` for the command line the user typed. The destination is
	/// fixed here, before anything runs, so delayed output cannot land in a
	/// conversation that has since been replaced.
	func execute(_ script: UserScript, input: String, target: String?) {
		let invocation = ScriptInvocation(session: self, target: target)
		guard scriptInvocationIsCurrent(invocation) else { return }
		switch script.kind {
		case .appleScript:
			executeAppleScript(script, input: input, target: target, invocation: invocation)
		case .unixExecutable:
			executeUnixScript(
				at: script.url,
				path: script.url.path,
				input: input,
				target: target,
				invocation: invocation
			)
		}
	}

	private func executeAppleScript(
		_ script: UserScript,
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
				for: UserScriptRunner.error(from: initializationError),
				forGlasstualCmdScriptAtPath: path,
				inputString: input
			)
			return
		}
		var executionError: NSDictionary?
		let event = UserScriptRunner.appleEvent(
			handler: UserScriptRunner.handlerName,
			input: input,
			target: target
		)
		let result = script.executeAppleEvent(event, error: &executionError)
		guard let executionError else {
			if let resultString = result.stringValue {
				sendGlasstualCmdScriptResult(resultString, to: invocation)
			}
			return
		}
		outputDescription(
			for: UserScriptRunner.error(from: executionError),
			forGlasstualCmdScriptAtPath: path,
			inputString: input
		)
	}

	private func executeUserAppleScript(
		at url: URL,
		path: String,
		input: String,
		target: String?,
		invocation: ScriptInvocation
	) {
		Task { [weak self] in
			let outcome: Result<String?, any Error>
			do {
				outcome = try await .success(UserScriptRunner.runUserAppleScript(
					at: url,
					handler: UserScriptRunner.handlerName,
					input: input,
					target: target
				))
			} catch {
				outcome = .failure(error)
			}

			guard let self, scriptInvocationIsCurrent(invocation) else { return }

			switch outcome {
			case let .success(resultString):
				if let resultString {
					sendGlasstualCmdScriptResult(resultString, to: invocation)
				}
			case let .failure(error):
				outputDescription(for: error, forGlasstualCmdScriptAtPath: path, inputString: input)
			}
		}
	}

	private func executeUnixScript(
		at url: URL,
		path: String,
		input: String,
		target: String?,
		invocation: ScriptInvocation
	) {
		let arguments = [target ?? ""] + input.components(separatedBy: .whitespaces)

		Task { [weak self] in
			let outcome: Result<String, any Error>
			do {
				let data = try await UserScriptRunner.runUnixScript(at: url, arguments: arguments)
				outcome = try .success(UserScriptRunner.decodedOutput(data))
			} catch {
				outcome = .failure(error)
			}

			guard let self, scriptInvocationIsCurrent(invocation) else { return }

			switch outcome {
			case let .success(text):
				sendGlasstualCmdScriptResult(text, to: invocation)
			case let .failure(error):
				outputDescription(for: error, forGlasstualCmdScriptAtPath: path, inputString: input)
			}
		}
	}
}
