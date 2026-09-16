/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
import os

nonisolated enum PreferencesTransferError: LocalizedError { // nonisolated: value
	case invalidDocument
	case unsupportedVersion
	case tooLarge
	case invalidValue(String)
	case stalePreview
	case connectionsDidNotClose
	case busy

	var errorDescription: String? {
		switch self {
		case .invalidDocument: String(localized: .PreferencesTransfer.fileIsNotAValidConfigurationSnapshot)
		case .unsupportedVersion: String(localized: .PreferencesTransfer.configurationSnapshotUsesANewerFormat)
		case .tooLarge: String(localized: .PreferencesTransfer.configurationFileExceedsSizeLimit)
		case .invalidValue: String(localized: .PreferencesTransfer.invalidValue)
		case .stalePreview: String(localized: .PreferencesTransfer.configurationChangedAfterPreview)
		case .connectionsDidNotClose: String(localized: .PreferencesTransfer.serversDidNotDisconnect)
		case .busy: String(localized: .PreferencesTransfer.configurationTransferInProgress)
		}
	}
}

/** One configuration, as a file carries it.

 An effective value and a deliberately unset key are two different things, so
 the archive records both: `values` is what the source had, `unset` is what it
 had deliberately removed. */
nonisolated struct PreferencesArchive: Equatable, Sendable { // nonisolated: value
	enum Source: Sendable {
		case portable, localRecovery
	}

	static let format = "GlasstualConfiguration"
	static let recoveryFormat = "GlasstualLocalRecovery"
	static let version = 1
	static let maximumBytes = 16 * 1024 * 1024
	/// What an export is offered as, and what an import expects to be handed.
	static let defaultArchiveFilename = "GlasstualPreferences.plist"
	var values: [String: PropertyListValue]
	var unset: Set<String>
	var clients: [ClientConfig]?
	var ignoredKeys: [String] = []
	/// Only this Mac's own snapshot, or a file read out of the protected
	/// recovery store, may claim local-recovery privileges; everything else is
	/// a file someone handed over.
	var source = Source.portable
	/// An omitted list preserves the target's commands; an included empty list clears them.
	var omittedConnectCommands: Set<String> = []

	func hasSameConfiguration(as other: Self) -> Bool {
		func configurations(_ clients: [ClientConfig]?) -> [[String: PropertyListValue]]? {
			clients?.map {
				var config = $0
				config.lastMessageServerTime = 0
				// Legacy decode scratch fields do not represent a configuration change.
				return config.dictionaryValue
			}
		}
		let ownConfigurations = configurations(clients)
		let otherConfigurations = configurations(other.clients)
		return values == other.values && unset == other.unset && ownConfigurations == otherConfigurations
	}

	func encoded(includeConnectCommands: Bool = false) throws -> Data {
		guard let clients else { throw PreferencesTransferError.invalidDocument }
		let configurations = clients.map { client in
			PreferencesClientArchive.portableDictionary(
				client,
				includeConnectCommands: includeConnectCommands
					&& !omittedConnectCommands.contains(client.uniqueIdentifier)
			)
		}
		return try encode(configurations: configurations, format: Self.format)
	}

	/// Only the protected recovery store uses this encoder. Portable export always sanitizes again.
	func recoveryEncoded() throws -> Data {
		guard source == .localRecovery, omittedConnectCommands.isEmpty, let clients else {
			throw PreferencesTransferError.invalidDocument
		}
		return try encode(
			configurations: clients.map { PreferencesClientArchive.withoutPendingSecrets($0).dictionaryValue },
			format: Self.recoveryFormat
		)
	}

	private func encode(configurations: [[String: PropertyListValue]], format: String) throws -> Data {
		guard let clients else { throw PreferencesTransferError.invalidDocument }
		guard clients.count == configurations.count else { throw PreferencesTransferError.invalidDocument }
		let dictionary: [String: PropertyListValue] = [
			"format": .string(format), "version": .integer(Self.version),
			"preferences": .dictionary(values), "unset": .init(unset.sorted()),
			"clients": .array(configurations.map(PropertyListValue.dictionary)),
		]
		let data = try PropertyListSerialization.data(
			fromPropertyList: dictionary.propertyListObject, format: .xml, options: 0
		)
		guard data.count <= Self.maximumBytes else { throw PreferencesTransferError.tooLarge }
		return data
	}

	static func decode(_ data: Data, source: Source = .portable) throws -> Self {
		guard data.count <= maximumBytes else { throw PreferencesTransferError.tooLarge }
		let object: Any
		do {
			object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
		} catch { throw PreferencesTransferError.invalidDocument }
		var remainingNodes = 200_000
		try checkBounds(object, depth: 0, remaining: &remainingNodes)
		guard let root = [String: PropertyListValue](propertyList: object) else {
			throw PreferencesTransferError.invalidDocument
		}
		let expectedFormat = source == .localRecovery ? recoveryFormat : format
		guard root["format"]?.string == expectedFormat else { throw PreferencesTransferError.invalidDocument }
		guard root["version"] == .integer(version) else { throw PreferencesTransferError.unsupportedVersion }
		guard let preferences = root["preferences"]?.dictionary,
		      let absent = root["unset"]?.stringArray, Set(absent).count == absent.count,
		      Set(absent).isDisjoint(with: preferences.keys), root["clients"]?.array != nil
		else { throw PreferencesTransferError.invalidDocument }
		/* A declared key the file names in neither list was declared after the
		 file was written. The file says nothing about it: Merge leaves the
		 local value alone and Restore returns it to its registered default,
		 so every key added later keeps older exports and backups readable. */
		var values = preferences
		var unset = Set(absent)
		let clientValue = root["clients"]
		var ignored: [String] = []
		for key in Set(values.keys).union(unset) {
			if Preferences.isExcludedFromExport(key) || key == Preferences.Connection.clientList.name {
				ignored.append(key)
				values.removeValue(forKey: key)
				unset.remove(key)
				continue
			}
			if let value = values[key] {
				guard let coerced = Preferences.coerce(value, forKey: key) else {
					throw PreferencesTransferError.invalidValue(key)
				}
				values[key] = coerced
			}
		}
		var clients = try clientValue.map(PreferencesClientArchive.decode)
		let omitted = Set((clientValue?.array ?? []).compactMap { value -> String? in
			guard let dictionary = value.dictionary,
			      dictionary[ClientConfig.CodingKeys.loginCommands.rawValue] == nil else { return nil }
			return dictionary[ClientConfig.CodingKeys.uniqueIdentifier.rawValue]?.string
		})
		if source == .localRecovery {
			guard omitted.isEmpty else { throw PreferencesTransferError.invalidDocument }
		} else {
			clients = clients?.map(PreferencesClientArchive.portable)
		}
		return Self(values: values, unset: unset, clients: clients, ignoredKeys: ignored.sorted(),
		            source: source, omittedConnectCommands: omitted)
	}

	private static func checkBounds(_ object: Any, depth: Int, remaining: inout Int) throws {
		guard depth <= 32, remaining > 0 else { throw PreferencesTransferError.tooLarge }
		remaining -= 1
		if let number = object as? NSNumber, !number.doubleValue.isFinite {
			throw PreferencesTransferError.invalidDocument
		}
		if let array = object as? [Any] {
			for value in array {
				try checkBounds(value, depth: depth + 1, remaining: &remaining)
			}
		} else if let dictionary = object as? [String: Any] {
			for value in dictionary.values {
				try checkBounds(value, depth: depth + 1, remaining: &remaining)
			}
		}
	}

	@concurrent
	static func read(from url: URL) async throws -> Self {
		try decode(readData(from: url))
	}

	static func readData(from url: URL) throws -> Data {
		let access = url.startAccessingSecurityScopedResource()
		defer {
			if access {
				url.stopAccessingSecurityScopedResource()
			}
		}
		let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
		guard attributes.isRegularFile == true else { throw PreferencesTransferError.invalidDocument }
		guard let size = attributes.fileSize, size <= maximumBytes else { throw PreferencesTransferError.tooLarge }
		let handle = try FileHandle(forReadingFrom: url)
		defer { try? handle.close() }
		let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
		guard data.count <= maximumBytes else { throw PreferencesTransferError.tooLarge }
		return data
	}
}

nonisolated enum PreferencesTransferMode: String, CaseIterable, Sendable { // nonisolated: value
	case merge
	case restore
}

/** A change an imported file makes that can run a command or widen what
 Glasstual trusts, which the preview spells out rather than counts. */
nonisolated enum PreferencesRiskyChange: Hashable, Sendable { // nonisolated: value
	/// A chat filter the file adds or changes whose action sends commands.
	case messageRuleAction(title: String, action: String)
	/// Link schemes the transcript would start treating as links.
	case linkSchemes([String])
	case developerMode
	/// What CTCP VERSION requests would be answered with.
	case ctcpVersionReply(String)
	/// Commands a server would send each time it connects.
	case connectCommands(server: String, commands: [String])
}

nonisolated struct PreferencesTransferPlan: Sendable { // nonisolated: value
	let before: PreferencesArchive
	let result: PreferencesArchive
	let changedKeys: [String]
	let removedKeys: [String]
	let addedClients: [String]
	let updatedClients: [String]
	let removedClients: [String]
	let riskyChanges: [PreferencesRiskyChange]
	let mode: PreferencesTransferMode

	init(archive: PreferencesArchive, current: PreferencesArchive, mode: PreferencesTransferMode) throws {
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
		for key in Preferences.allKeys {
			if let value = result.values[key.name] ?? key.registeredDefault,
			   !key.isValid(value, in: result.values)
			{
				throw PreferencesTransferError.invalidValue(key.name)
			}
		}
		// A name made at runtime has no declaration of its own, so its family
		// answers for the shape it may hold.
		for (name, value) in result.values where Preferences.key(named: name) == nil {
			guard Preferences.coerce(value, forKey: name) != nil else {
				throw PreferencesTransferError.invalidValue(name)
			}
		}
		let currentClients = current.clients ?? []
		let importedClients = (archive.clients ?? []).map {
			var client = $0
			let existing = currentClients.first { $0.uniqueIdentifier == client.uniqueIdentifier }
			if archive.omittedConnectCommands.contains(client.uniqueIdentifier) {
				client.loginCommands = existing?.loginCommands ?? []
			}
			if archive.source == .portable {
				client.identityClientSideCertificate = existing?.identityClientSideCertificate
			}
			client.autoConnect = false
			return client
		}
		var clients = mode == .restore ? [] : currentClients
		for client in importedClients {
			if let index = clients.firstIndex(where: { $0.uniqueIdentifier == client.uniqueIdentifier }) {
				clients[index] = client
			} else {
				clients.append(client)
			}
		}
		result.clients = clients
		self.result = result
		/* Compared as the stores would read them back: a snapshot records a
		 registered key's default as its value, so writing a key absent is only a
		 change when this Mac holds something other than that default. */
		func effective(_ values: [String: PropertyListValue], _ name: String) -> PropertyListValue? {
			values[name] ?? Preferences.key(named: name)?.registeredDefault
		}
		changedKeys = Set(current.values.keys).union(result.values.keys).filter {
			effective(current.values, $0) != effective(result.values, $0)
		}.sorted()
		removedKeys = changedKeys.filter { result.values[$0] == nil }
		addedClients = clients
			.filter { client in !currentClients.contains { $0.uniqueIdentifier == client.uniqueIdentifier } }
			.map(\.connectionName)
		updatedClients = clients.filter { client in
			currentClients.contains { $0.uniqueIdentifier == client.uniqueIdentifier && $0 != client }
		}.map(\.connectionName)
		removedClients = currentClients
			.filter { client in !clients.contains { $0.uniqueIdentifier == client.uniqueIdentifier } }
			.map(\.connectionName)
		riskyChanges = Self.riskyChanges(from: current, to: result)
	}

	/** Everything the plan changes that the preview has to show in full.

	 A count tells the reader nothing about a filter that answers every message
	 with `/msg`, a scheme that makes `file:` text clickable, or a command a
	 server runs on connect, so each is reported with its content. */
	private static func riskyChanges(
		from current: PreferencesArchive, to result: PreferencesArchive
	) -> [PreferencesRiskyChange] {
		var changes: [PreferencesRiskyChange] = []

		let filters = Preferences.Rules.messageRules.name
		let currentActions = PreferenceValueRepair.messageRuleActions(in: current.values[filters])
		for (identifier, filter) in PreferenceValueRepair.messageRuleActions(in: result.values[filters])
			.sorted(by: { $0.key < $1.key })
			where filter.action.isEmpty == false && currentActions[identifier]?.action != filter.action
		{
			changes.append(.messageRuleAction(title: filter.title, action: filter.action))
		}

		func schemes(in archive: PreferencesArchive) -> Set<String> {
			let keys = [Preferences.LinkSchemes.permittedDefault, Preferences.LinkSchemes.permitted]
			return Set(keys.flatMap { key in
				(archive.values[key.name] ?? key.registeredDefault)?.stringArray ?? []
			})
		}
		let addedSchemes = schemes(in: result).subtracting(schemes(in: current))
		if addedSchemes.isEmpty == false {
			changes.append(.linkSchemes(addedSchemes.sorted()))
		}

		let developerMode = Preferences.Commands.developerMode.name
		if result.values[developerMode]?.boolean == true, current.values[developerMode]?.boolean != true {
			changes.append(.developerMode)
		}

		let versionReply = Preferences.Identity.ctcpVersionMasquerade.name
		if let reply = result.values[versionReply]?.string, reply.isEmpty == false,
		   current.values[versionReply]?.string != reply
		{
			changes.append(.ctcpVersionReply(reply))
		}

		for client in result.clients ?? [] where client.loginCommands.isEmpty == false {
			let existing = current.clients?.first { $0.uniqueIdentifier == client.uniqueIdentifier }
			if existing?.loginCommands != client.loginCommands {
				changes.append(.connectCommands(server: client.connectionName, commands: client.loginCommands))
			}
		}

		return changes
	}
}
