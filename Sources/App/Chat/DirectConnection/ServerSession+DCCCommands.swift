// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** `/dcc`: offering files and chats, answering the questions DCC asks, and
 managing the certificates secure connections are trusted by.

 Every question a DCC alert asks can be answered here too, by the short
 identifier the transcript prints beside it, so nothing about a connection
 depends on the alert being on screen. */
extension ServerSession {
	/// `/dcc` or `/xdcc`, whichever `group` names.
	func dispatchDirectConnectionCommand(
		_ group: LocalCommand.Group,
		parsed: ParsedUserCommand,
		targetConversation: Conversation?
	) {
		if group == .xdcc {
			handleXDCCCommand(parsed.arguments, command: parsed.command, targetConversation: targetConversation)
		} else {
			handleDCCCommand(parsed.arguments, command: parsed.command, targetConversation: targetConversation)
		}
	}

	func handleDCCCommand(
		_ input: CommandArguments,
		command: String,
		targetConversation: Conversation?
	) {
		var input = input
		let subcommand = input.next().lowercased()
		switch subcommand {
		case "chat", "schat":
			let secure = subcommand == "schat" || environment.settings.fileTransferOffersAreSecure
			startDirectChat(from: &input, secure: secure, command: command, targetConversation: targetConversation)
		case "send", "ssend":
			let secure = subcommand == "ssend" || environment.settings.fileTransferOffersAreSecure
			offerFile(from: &input, secure: secure, command: command)
		case "accept", "decline", "trust":
			/* Answering a question is the message field's: the window reads
			 these before a typed line gets here. */
			refuseUntypedPromptAnswer()
		case "fingerprint":
			printOwnDCCFingerprint()
		case "certificates":
			let nickname = input.next()
			printSavedDCCCertificates(for: nickname.isEmpty ? nil : nickname)
		case "forget":
			let nickname = input.next()
			guard nickname.isEmpty == false else {
				printInvalidSyntaxMessage(for: command)
				return
			}
			forgetDCCCertificates(for: nickname)
		default:
			printInvalidSyntaxMessage(for: command)
		}
	}

	private func startDirectChat(
		from input: inout CommandArguments,
		secure: Bool,
		command: String,
		targetConversation: Conversation?
	) {
		guard isLoggedIn else {
			printDebugInformation(toConsole: String(localized: .IRC.failedToSendDataToServer))
			return
		}
		var nickname = input.next()
		if nickname.isEmpty, let targetConversation {
			if targetConversation.isDirect {
				nickname = targetConversation.name
			} else if targetConversation.isDirectChat {
				nickname = targetConversation.directChatConnection?
					.peerNickname ?? String(targetConversation.name.dropFirst())
			}
		}
		guard !nickname.isEmpty, stringIsNickname(nickname) else {
			printInvalidSyntaxMessage(for: command)
			return
		}
		startDirectChat(withNickname: nickname, secure: secure)
	}

	private func offerFile(from input: inout CommandArguments, secure: Bool, command: String) {
		let nickname = input.next()
		let path = (input.rest.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
		guard !nickname.isEmpty, stringIsNickname(nickname), !path.isEmpty else {
			printInvalidSyntaxMessage(for: command)
			return
		}
		fileTransfers?.offerSender(
			for: self, nickname: nickname, path: path, autoOpen: true, accessURL: nil, secure: secure
		) { [weak self] identifier in
			if identifier == nil {
				self?.printDebugInformation(String(localized: .IRC.fileAtCouldNotBeOffered(path)))
			}
		}
	}

	// MARK: - Certificates

	private func printOwnDCCFingerprint() {
		Task { [weak self] in
			guard let self else { return }
			do {
				let identity = try await dccLocalIdentity()
				printDebugInformation(String(localized: .IRC.dccOwnFingerprint(identity.fingerprint.formatted)))
			} catch {
				printDebugInformation(String(localized: .IRC.dccOwnFingerprintUnavailable(error.localizedDescription)))
			}
		}
	}

	private func printSavedDCCCertificates(for nickname: String?) {
		let store = environment.services.dccPeerCertificates
		let network = config.uniqueIdentifier
		let caseMapping = supportInfo.caseMapping
		Task { [weak self] in
			let pins: [DCCPeerPin] = if let nickname {
				await store.pins(network: network, nickname: nickname, caseMapping: caseMapping)
			} else {
				await store.all()[network]?.values.flatMap(\.self) ?? []
			}
			guard let self else { return }
			guard pins.isEmpty == false else {
				printDebugInformation(String(localized: nickname.map { .IRC.dccSavedCertificatesNoneForNickname($0) }
						?? .IRC.dccSavedCertificatesNone))
				return
			}
			for pin in pins.sorted(by: { $0.nickname.localizedStandardCompare($1.nickname) == .orderedAscending }) {
				printDebugInformation(String(localized: .IRC.dccSavedCertificateRow(
					pin.nickname,
					pin.fingerprint.formatted,
					pin.firstTrusted.formatted(date: .abbreviated, time: .shortened),
					pin.lastSeen.formatted(date: .abbreviated, time: .shortened)
				)))
			}
		}
	}

	private func forgetDCCCertificates(for nickname: String) {
		let store = environment.services.dccPeerCertificates
		let network = config.uniqueIdentifier
		let caseMapping = supportInfo.caseMapping
		Task { [weak self] in
			do {
				try await store.forget(network: network, nickname: nickname, caseMapping: caseMapping)
				self?.printDebugInformation(String(localized: .IRC.dccSavedCertificatesForgotten(nickname)))
			} catch {
				self?.printDebugInformation(
					String(localized: .IRC.dccSavedCertificatesForgetFailed(nickname, error.localizedDescription))
				)
			}
		}
	}
}
