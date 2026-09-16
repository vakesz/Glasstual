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
	case legacyRestore
	case stalePreview
	case connectionsDidNotClose
	case busy

	var errorDescription: String? {
		switch self {
		case .invalidDocument: String(localized: .PreferencesTransfer.fileIsNotAValidConfigurationSnapshot)
		case .unsupportedVersion: String(localized: .PreferencesTransfer.configurationSnapshotUsesANewerFormat)
		case .tooLarge: String(localized: .PreferencesTransfer.configurationFileExceedsSizeLimit)
		case .invalidValue: String(localized: .PreferencesTransfer.invalidValue)
		case .legacyRestore: String(localized: .PreferencesTransfer.legacyNotice)
		case .stalePreview: String(localized: .PreferencesTransfer.configurationChangedAfterPreview)
		case .connectionsDidNotClose: String(localized: .PreferencesTransfer.serversDidNotDisconnect)
		case .busy: String(localized: .PreferencesTransfer.configurationTransferInProgress)
		}
	}
}

/// Complete archives distinguish an effective value from a deliberately unset key.
/// Legacy dictionaries have neither that distinction nor permission to remove data.
nonisolated struct PreferencesArchive: Equatable, Sendable { // nonisolated: value
	enum Source: Sendable {
		case portable, localRecovery
	}

	static let format = "GlasstualConfiguration"
	static let recoveryFormat = "GlasstualLocalRecovery"
	static let version = 1
	static let maximumBytes = 16 * 1024 * 1024
	let isComplete: Bool
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
		guard isComplete, let clients else { throw PreferencesTransferError.invalidDocument }
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
		let complete = root["format"] != nil || root["version"] != nil || root["preferences"] != nil
		var values: [String: PropertyListValue]
		var unset: Set<String> = []
		let clientValue: PropertyListValue?
		if complete {
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
			values = preferences
			unset = Set(absent)
			clientValue = root["clients"]
		} else {
			guard source == .portable else { throw PreferencesTransferError.invalidDocument }
			values = root
			clientValue = values.removeValue(forKey: Preferences.Connection.clientList.name)
		}
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
		return Self(isComplete: complete, values: values, unset: unset, clients: clients, ignoredKeys: ignored.sorted(),
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

private let repairLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Glasstual", category: "Preferences")

/// What the launch repair changed, and where the values it replaced were kept.
struct PreferencesStoredValueRepair: Equatable {
	/// Keys that kept the elements their declaration still accepts.
	var repaired: Set<String> = []
	/// Keys whose stored value was removed, leaving the registered default.
	var removed: Set<String> = []
	/// The private file holding every replaced value as it was stored.
	var backup: URL?
}

/// The standard store is an explicit dependency, including in tests. No suite override
/// changes process-global UserDefaults.standard or the user's registration domain.
struct PreferencesTransferStores {
	let container: UserDefaults
	let containerDomain: String
	let standard: UserDefaults
	let standardDomain: String

	static var live: Self {
		Self(container: GlasstualUserDefaults.container, containerDomain: GlasstualUserDefaults.container.suiteName,
		     standard: .standard,
		     standardDomain: Bundle.main.bundleIdentifier ?? ApplicationInfo.applicationBundleIdentifier())
	}

	func store(for key: some AnyPreferenceKey) -> UserDefaults {
		key.storage == .standard ? standard : container
	}

	/// What a store actually holds, without the registration domain that
	/// `object(forKey:)` falls back to. `nil` means nothing is persisted, which
	/// is a different answer from "the registered default".
	func persistedValue(for key: some AnyPreferenceKey) -> PropertyListValue? {
		persistentDomain(for: key.storage)[key.name].flatMap(PropertyListValue.init(propertyList:))
	}

	/** Everything a domain has persisted, read from the current-user, any-host
	 source a suite writes to.

	 `persistentDomain(forName:)` answers the same question, but it also opens
	 the any-user, by-host source, which cfprefsd refuses for an application
	 group container: it detaches from the domain and logs "Using
	 kCFPreferencesAnyUser with a container is only allowed for System
	 Containers" every time it is asked. */
	func persistentDomain(for storage: PreferenceStorage) -> [String: Any] {
		let domain = (storage == .standard ? standardDomain : containerDomain) as CFString
		guard let names = CFPreferencesCopyKeyList(
			domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost
		) as? [String] else { return [:] }
		var values: [String: Any] = [:]
		values.reserveCapacity(names.count)
		for name in names {
			if let value = CFPreferencesCopyValue(
				name as CFString, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost
			) {
				values[name] = value
			}
		}
		return values
	}

	subscript<Value>(key: PreferenceKey<Value>) -> Value {
		self[stored: key] ?? key.defaultValue
	}

	subscript<Value>(stored key: PreferenceKey<Value>) -> Value? {
		store(for: key).object(forKey: key.name).flatMap(Value.preferenceValue(from:))
	}

	func set(_ value: PropertyListValue?, for key: some AnyPreferenceKey) {
		let store = store(for: key)
		if let value {
			store.set(value.propertyListObject, forKey: key.name)
		} else {
			store.removeObject(forKey: key.name)
		}
	}

	/** Repairs or removes every persisted value a declaration would refuse.

	 Bounds arrive after values do: a count or port stored before its range was
	 declared, or by an older build, reads back exactly as it was stored.
	 Everything downstream holds values to the declarations — the Settings
	 fields, an export, the recovery backup taken before an import, the import
	 plan itself — so one stale value would make all of them fail on this
	 Mac's own state.

	 A collection keeps every element the declaration still accepts; only a
	 value with nothing left to keep is removed, which leaves the registered
	 default in its place. Before anything is written, the values as they were
	 stored are saved to a private file in `backupDirectory`, and if that save
	 fails nothing is changed. Runs once at launch, before anything reads. */
	@discardableResult
	func repairValuesDeclarationsRefuse(backupDirectory: URL) -> PreferencesStoredValueRepair {
		let persisted: [PreferenceStorage: [String: Any]] = [
			.container: persistentDomain(for: .container),
			.standard: persistentDomain(for: .standard),
		]
		var values: [String: PropertyListValue] = [:]
		var repaired: [String: PropertyListValue] = [:]
		var removed: Set<String> = []
		var originals: [String: Any] = [:]
		for key in Preferences.allKeys {
			guard let object = persisted[key.storage]?[key.name] else { continue }
			let value = PropertyListValue(propertyList: object)
			if let value, let coerced = Preferences.coerce(value, forKey: key.name) {
				values[key.name] = coerced
				continue
			}
			originals[key.name] = object
			if let value, let salvaged = Preferences.salvage(value, forKey: key.name) {
				values[key.name] = salvaged
				repaired[key.name] = salvaged
			} else {
				removed.insert(key.name)
			}
		}
		// A value that is fine on its own can still contradict its partner.
		for key in Preferences.allKeys {
			if let value = values[key.name], !key.isValid(value, in: values) {
				originals[key.name] = persisted[key.storage]?[key.name]
				repaired.removeValue(forKey: key.name)
				removed.insert(key.name)
			}
		}
		guard originals.isEmpty == false else { return PreferencesStoredValueRepair() }

		let backup: URL
		do {
			let data = try PropertyListSerialization.data(fromPropertyList: originals, format: .xml, options: 0)
			backup = try PreferencesProtectedFolder(url: backupDirectory)
				.write(data, named: "Repaired-Settings-\(UUID().uuidString).plist")
		} catch {
			repairLogger.error("""
			Left \(originals.count, privacy: .public) refused stored settings unchanged: \
			their backup could not be written: \(error.localizedDescription, privacy: .public)
			""")
			return PreferencesStoredValueRepair()
		}
		for (name, value) in repaired {
			set(value, for: UntypedPreferenceKey(name, storage: Preferences.storage(for: name)))
			repairLogger.notice("Dropped refused entries from \(name, privacy: .public).")
		}
		for name in removed {
			set(nil, for: UntypedPreferenceKey(name, storage: Preferences.storage(for: name)))
			repairLogger.notice("Removed the refused stored value of \(name, privacy: .public).")
		}
		repairLogger.notice("Saved the settings as they were stored to \(backup.path, privacy: .private).")
		return PreferencesStoredValueRepair(repaired: Set(repaired.keys), removed: removed, backup: backup)
	}

	func snapshot(clients: [ClientConfig]) -> PreferencesArchive {
		var values: [String: PropertyListValue] = [:]
		var unset: Set<String> = []
		for key in Preferences.allKeys where !Preferences.isExcludedFromExport(key.name)
			&& key.name != Preferences.Connection.clientList.name
		{
			if let value = store(for: key).object(forKey: key.name).flatMap(PropertyListValue.init(propertyList:))
				?? key.registeredDefault
			{
				values[key.name] = value
			} else {
				unset.insert(key.name)
			}
		}
		for storage in PreferenceStorage.allCases {
			for (name, object) in persistentDomain(for: storage)
				where Preferences.key(named: name) == nil && !Preferences.isExcludedFromExport(name)
			{
				guard Preferences.storage(for: name) == storage else { continue }
				values[name] = PropertyListValue(propertyList: object)
			}
		}
		return PreferencesArchive(isComplete: true, values: values, unset: unset,
		                          clients: clients.map(PreferencesClientArchive.withoutPendingSecrets),
		                          source: .localRecovery)
	}

	func apply(_ plan: PreferencesTransferPlan, persistClients: Bool = true) {
		for name in plan.changedKeys {
			let key = UntypedPreferenceKey(name, storage: Preferences.storage(for: name))
			set(plan.result.values[name], for: key)
		}
		if persistClients {
			set(
				.array((plan.result.clients ?? []).map { .dictionary($0.dictionaryValue) }),
				for: Preferences.Connection.clientList
			)
		}
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
		guard mode != .restore || archive.isComplete else { throw PreferencesTransferError.legacyRestore }
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
		let currentActions = PreferencesPayloadValidation.messageRuleActions(in: current.values[filters])
		for (identifier, filter) in PreferencesPayloadValidation.messageRuleActions(in: result.values[filters])
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
