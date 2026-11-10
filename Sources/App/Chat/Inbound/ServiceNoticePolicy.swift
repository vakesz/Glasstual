// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

enum ServiceNoticePolicy {
	struct ChannelNotice {
		let channelName: String
		let text: String
	}

	enum NickServAction: Equatable {
		case sendIdentification(target: String, text: String)
		/// Services asked for the password, and the connection may not carry it.
		case identificationWithheld
		case identificationSucceeded
	}

	struct NickServContext {
		let isWaiting: Bool
		/// Whether SASL already authenticated the account. Services still ask
		/// a nickname that is identified to identify on some networks, and the
		/// answer would be a second copy of the password for nothing.
		let isIdentifiedWithSASL: Bool
		/// Whether the connection may carry the password; see
		/// `ServerSession.permitsCredentialsInClear`.
		let permitsCredentialsInClear: Bool
		let password: String?
		let nickname: String
		let serverAddress: String?
		let sendsAuthenticationToUserServ: Bool
		let needsIdentificationTokens: [String]
		let successfulIdentificationTokens: [String]
	}

	/** Whether a `NickServ` or `ChanServ` notice plausibly came from network services.

	 The reply to a NickServ notice carries the account password, and a ChanServ
	 notice is filed into the channel it names. Nothing stops an ordinary user
	 from holding either nickname on a network without nickname protection, so
	 the sender has to be the network's before either happens.

	 The host alone cannot say so. A reverse DNS name is whatever the owner of
	 the address publishes, so `services.attacker.example` is one record away
	 for anyone; what an ordinary user cannot have is a host inside the domain
	 of the server the session connected to. Services therefore count when they
	 are the server itself, when their host is under the network's own domain
	 (`NickServ!service@dal.net` against `irc.dal.net`), or when a `services`
	 label sits directly on that domain (`services.libera.chat` against
	 `irc.libera.chat`). The bare `services.` host some networks use is not a
	 name DNS can produce, so only the network can have given it. */
	static func noticeIsFromServices(
		senderIsServer: Bool,
		senderAddress: String?,
		serverAddress: String?
	) -> Bool {
		if senderIsServer {
			return true
		}

		guard let address = senderAddress?.lowercased(), address.isEmpty == false else {
			return false
		}

		if address == "services." {
			return true
		}

		guard let serverAddress = serverAddress?.lowercased(), serverAddress.isEmpty == false else {
			return false
		}

		var labels = address.split(separator: ".", omittingEmptySubsequences: false)

		/* `services.example.net` and `nick.services.example.net` both name the
		 domain after their `services` label; a host with no such label names
		 its own. */
		if let servicesLabel = labels.lastIndex(of: "services") {
			labels.removeSubrange(...servicesLabel)
		}

		return domain(labels.joined(separator: "."), contains: serverAddress)
	}

	/// Whether `host` is `domain` or sits under it. A single label is a
	/// top-level domain, never a network's own, so it contains nothing.
	private static func domain(_ domain: String, contains host: String) -> Bool {
		let labels = domain.split(separator: ".", omittingEmptySubsequences: false)

		guard labels.count >= 2, labels.allSatisfy({ $0.isEmpty == false }) else {
			return false
		}

		return host == domain || host.hasSuffix("." + domain)
	}

	static func channelNotice(from text: String) -> ChannelNotice? {
		guard text.hasPrefix("["), let space = text.firstIndex(of: " ") else { return nil }
		let head = text[..<space]
		guard head.count >= 4, head.hasSuffix("]") else { return nil }
		return ChannelNotice(
			channelName: String(head.dropFirst().dropLast()),
			text: String(text[text.index(after: space)...])
		)
	}

	static func nickServAction(for text: String, context: NickServContext) -> NickServAction? {
		/* Whether or not this session is the one that asked: a connect command
		 may have sent the identification, and the service confirms it the
		 same way. */
		if context.successfulIdentificationTokens.contains(where: text.localizedCaseInsensitiveContains) {
			return .identificationSucceeded
		}
		guard context.needsIdentificationTokens.contains(where: text.localizedCaseInsensitiveContains) else {
			return nil
		}
		return identificationAction(for: context)
	}

	/** What to do about a nickname that has to identify, whatever prompted it:
	 a notice from services, or the user allowing a password that was held back. */
	static func identificationAction(for context: NickServContext) -> NickServAction? {
		if context.isWaiting || context.isIdentifiedWithSASL {
			return nil
		}

		guard let password = context.password, !password.isEmpty else { return nil }
		guard context.permitsCredentialsInClear else {
			return .identificationWithheld
		}
		if context.serverAddress?.hasSuffix(ServerQuirks.Services.dalNetAddressSuffix) == true {
			return .sendIdentification(
				target: ServerQuirks.Services.dalNetNickServTarget,
				text: "IDENTIFY \(password)"
			)
		}
		if context.sendsAuthenticationToUserServ {
			return .sendIdentification(
				target: ServerQuirks.Services.userServTarget,
				text: "login \(context.nickname) \(password)"
			)
		}
		return .sendIdentification(target: ServerQuirks.Services.nickServ, text: "IDENTIFY \(password)")
	}
}

/** The NickServ phrase lists, read from the bundled property list once.

 Both lists are consulted for every notice a service sends, and the file they
 come from cannot change while the process runs, so reading them per notice
 parsed the same property list over and over. */
nonisolated enum NickServTokens {
	static let needsIdentification = tokens(forKey: StaticStoreResource.nickServNeedsIdentificationTokensKey)
	static let identified = tokens(forKey: StaticStoreResource.nickServIdentifiedTokensKey)

	private static func tokens(forKey key: String) -> [String] {
		BundleResources.array(fromResources: StaticStoreResource.name, key: key)?
			.compactMap(\.string) ?? []
	}
}
