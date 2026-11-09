// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** A change an imported file makes that can run a command or widen what
 Glasstual trusts, which the preview spells out rather than counts. */
nonisolated enum SettingsRiskyChange: Hashable, Sendable {
	/// A chat filter the file adds or changes whose action sends commands.
	case messageRuleAction(title: String, action: String)
	/// Link schemes the transcript would start treating as links.
	case linkSchemes([String])
	case developerMode
	/// What CTCP VERSION requests would be answered with.
	case ctcpVersionReply(String)
	/// Commands a server would send each time it connects.
	case connectCommands(server: String, commands: [String])
	/// A server the file points somewhere other than where this Mac's copy goes.
	case serverEndpoint(server: String, from: Endpoint, to: Endpoint, outcome: EndpointOutcome)
	/// A server that connects without checking the certificate chain it is shown.
	case certificateValidationDisabled(server: String)

	/// Where a server connects, as the preview names it.
	struct Endpoint: Hashable, Sendable {
		let host: String
		let port: UInt16
		let isEncrypted: Bool
	}

	/// What the import does with the server whose endpoint moved.
	enum EndpointOutcome: Hashable, Sendable {
		/// The server is updated in place and keeps its saved passwords.
		case sameServer
		/// The file's server is added beside this Mac's, which keeps its secrets and history.
		case newServerExistingKept
		/// The file's server replaces this Mac's, whose secrets and history stay behind.
		case newServerExistingRemoved
	}
}

nonisolated struct SettingsTransferPlan: Sendable {
	let before: SettingsArchive
	let result: SettingsArchive
	let changedKeys: [String]
	let removedKeys: [String]
	let addedSessions: [String]
	let updatedSessions: [String]
	let removedSessions: [String]
	let riskyChanges: [SettingsRiskyChange]
	let mode: SettingsTransferMode

	init(archive: SettingsArchive, current: SettingsArchive, mode: SettingsTransferMode) throws {
		before = current
		self.mode = mode
		var result = current
		if mode == .restore {
			// A key the file does not name is written as absent, which reads back
			// as its registered default.
			result.values = archive.values
			result.unset = archive.unset
		} else {
			/* Merge only writes what the file carries. `unset` is where a snapshot
			 records a list the source never created — its chat filters, its
			 highlight words — and that is no reason to delete this Mac's. */
			result.values.merge(archive.values) { _, imported in imported }
			result.unset.subtract(archive.values.keys)
		}
		for key in SettingsKeys.allKeys {
			if let value = result.values[key.name] ?? key.registeredDefault,
			   !key.isValid(value, in: result.values)
			{
				throw SettingsTransferError.invalidValue(key.name)
			}
		}
		// A name made at runtime has no declaration of its own, so its family
		// answers for the shape it may hold.
		for (name, value) in result.values where SettingsKeys.key(named: name) == nil {
			guard SettingsKeys.coerce(value, forKey: name) != nil else {
				throw SettingsTransferError.invalidValue(name)
			}
		}
		let currentSessions = current.sessions ?? []
		var sessionRisks: [SettingsRiskyChange] = []
		var importedSessions: [ServerConfig] = []
		for imported in archive.sessions ?? [] {
			let identifier = imported.uniqueIdentifier
			let existing = currentSessions.first { $0.uniqueIdentifier == identifier }
			var session = imported
			/* Secrets are filed under the identifiers of the session that owns
			 them, so a file that sends a known session somewhere new would carry
			 its passwords there. That one becomes a different network, with
			 identities nothing is stored under. A backup this app wrote itself
			 is restoring its own history and is left alone. */
			let reidentified = archive.source == .portable
				&& existing.map { Self.widensCredentialDestinations(from: $0, to: imported) } == true
			if reidentified {
				session = imported.reidentified(derivedFrom: Self.destinationFingerprint(of: imported))
			}
			if archive.omittedConnectCommands.contains(identifier) {
				session.loginCommands = reidentified ? [] : existing?.loginCommands ?? []
			}
			if archive.source == .portable {
				session.identityClientSideCertificate = reidentified ? nil : existing?.identityClientSideCertificate
				// An earlier import already made this network, and already showed this.
				let isAlreadyImported = reidentified
					&& currentSessions.contains { $0.uniqueIdentifier == session.uniqueIdentifier }
				if isAlreadyImported == false {
					sessionRisks.append(contentsOf: Self.endpointRisks(
						existing: existing, imported: imported, reidentifiedAs: reidentified ? mode : nil
					))
				}
			}
			session.autoConnect = false
			importedSessions.append(session)
		}
		var sessions = mode == .restore ? [] : currentSessions
		for session in importedSessions {
			if let index = sessions.firstIndex(where: { $0.uniqueIdentifier == session.uniqueIdentifier }) {
				sessions[index] = session
			} else {
				sessions.append(session)
			}
		}
		result.sessions = sessions
		self.result = result
		/* Compared as the stores would read them back: a snapshot records a
		 registered key's default as its value, so writing a key absent is only a
		 change when this Mac holds something other than that default. */
		func effective(_ values: [String: PropertyListValue], _ name: String) -> PropertyListValue? {
			values[name] ?? SettingsKeys.key(named: name)?.registeredDefault
		}
		changedKeys = Set(current.values.keys).union(result.values.keys).filter {
			effective(current.values, $0) != effective(result.values, $0)
		}.sorted()
		removedKeys = changedKeys.filter { result.values[$0] == nil }
		addedSessions = sessions
			.filter { session in !currentSessions.contains { $0.uniqueIdentifier == session.uniqueIdentifier } }
			.map(\.connectionName)
		updatedSessions = sessions.filter { session in
			currentSessions.contains { $0.uniqueIdentifier == session.uniqueIdentifier && $0 != session }
		}.map(\.connectionName)
		removedSessions = currentSessions
			.filter { session in !sessions.contains { $0.uniqueIdentifier == session.uniqueIdentifier } }
			.map(\.connectionName)
		riskyChanges = sessionRisks + Self.riskyChanges(from: current, to: result)
	}

	// MARK: - Where a session's credentials would go

	/** The places a session sends its credentials: every server it can connect
	 to, and the proxy that carries the connection when one is configured. */
	private static func credentialDestinations(of session: ServerConfig) -> Set<String> {
		var destinations = Set(session.serverList.map { "\($0.serverAddress.lowercased()):\($0.serverPort)" })
		if session.proxyType == .socks5 || session.proxyType == .HTTP, let address = session.proxyAddress {
			destinations.insert("proxy-\(session.proxyType.rawValue):\(address.lowercased()):\(session.proxyPort)")
		}
		return destinations
	}

	/// Whether `imported` reaches a destination `existing` does not. Dropping or
	/// reordering servers sends nothing anywhere new.
	private static func widensCredentialDestinations(from existing: ServerConfig, to imported: ServerConfig) -> Bool {
		credentialDestinations(of: imported).isSubset(of: credentialDestinations(of: existing)) == false
	}

	private static func destinationFingerprint(of session: ServerConfig) -> String {
		credentialDestinations(of: session).sorted().joined(separator: "|")
	}

	private static func endpoint(of session: ServerConfig) -> SettingsRiskyChange.Endpoint? {
		session.serverList.first.map {
			.init(host: $0.serverAddress, port: $0.serverPort, isEncrypted: $0.prefersSecuredConnection)
		}
	}

	/** What the preview says about the endpoint and certificate checking of one
	 imported session. `reidentifiedAs` is the mode when the session became a new
	 network, and nil when it did not. */
	private static func endpointRisks(
		existing: ServerConfig?, imported: ServerConfig, reidentifiedAs mode: SettingsTransferMode?
	) -> [SettingsRiskyChange] {
		var risks: [SettingsRiskyChange] = []
		if let existing, let from = endpoint(of: existing), let to = endpoint(of: imported),
		   from.host.caseInsensitiveCompare(to.host) != .orderedSame || from.port != to.port
		   || from.isEncrypted != to.isEncrypted
		{
			let outcome: SettingsRiskyChange.EndpointOutcome = switch mode {
			case .merge?: .newServerExistingKept
			case .restore?: .newServerExistingRemoved
			case nil: .sameServer
			}
			risks.append(.serverEndpoint(server: imported.connectionName, from: from, to: to, outcome: outcome))
		}
		if imported.validateServerCertificateChain == false,
		   existing?.validateServerCertificateChain ?? true
		{
			risks.append(.certificateValidationDisabled(server: imported.connectionName))
		}
		return risks
	}

	/** Everything the plan changes that the preview has to show in full.

	 A count tells the reader nothing about a filter that answers every message
	 with `/msg`, a scheme that makes `file:` text clickable, or a command a
	 server runs on connect, so each is reported with its content. */
	private static func riskyChanges(
		from current: SettingsArchive, to result: SettingsArchive
	) -> [SettingsRiskyChange] {
		var changes: [SettingsRiskyChange] = []

		let filters = SettingsKeys.Rules.messageRules.name
		let currentActions = SettingsValueRepair.messageRuleActions(in: current.values[filters])
		for (identifier, filter) in SettingsValueRepair.messageRuleActions(in: result.values[filters])
			.sorted(by: { $0.key < $1.key })
			where filter.action.isEmpty == false && currentActions[identifier]?.action != filter.action
		{
			changes.append(.messageRuleAction(title: filter.title, action: filter.action))
		}

		func schemes(in archive: SettingsArchive) -> Set<String> {
			let keys = [SettingsKeys.LinkSchemes.permittedDefault, SettingsKeys.LinkSchemes.permitted]
			return Set(keys.flatMap { key in
				(archive.values[key.name] ?? key.registeredDefault)?.stringArray ?? []
			})
		}
		let addedSchemes = schemes(in: result).subtracting(schemes(in: current))
		if addedSchemes.isEmpty == false {
			changes.append(.linkSchemes(addedSchemes.sorted()))
		}

		let developerMode = SettingsKeys.Commands.developerMode.name
		if result.values[developerMode]?.boolean == true, current.values[developerMode]?.boolean != true {
			changes.append(.developerMode)
		}

		let versionReply = SettingsKeys.Identity.ctcpVersionMasquerade.name
		if let reply = result.values[versionReply]?.string, reply.isEmpty == false,
		   current.values[versionReply]?.string != reply
		{
			changes.append(.ctcpVersionReply(reply))
		}

		for session in result.sessions ?? [] where session.loginCommands.isEmpty == false {
			let existing = current.sessions?.first { $0.uniqueIdentifier == session.uniqueIdentifier }
			if existing?.loginCommands != session.loginCommands {
				changes.append(.connectCommands(server: session.connectionName, commands: session.loginCommands))
			}
		}

		return changes
	}
}

extension SettingsTransferPlan {
	/// Writes this plan's result into `stores`.
	func apply(to stores: SettingsStores, persistSessions: Bool = true) {
		for name in changedKeys {
			let key = UntypedSettingsKey(name, storage: SettingsKeys.storage(for: name))
			stores.set(result.values[name], for: key)
		}
		if persistSessions {
			stores.set(
				.array((result.sessions ?? []).map { .dictionary($0.dictionaryValue) }),
				for: SettingsKeys.Sessions.serverSessions
			)
		}
	}
}
