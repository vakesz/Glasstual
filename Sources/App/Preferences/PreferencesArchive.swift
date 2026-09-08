/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation

nonisolated enum PreferencesTransferError: LocalizedError { // nonisolated: value
	case invalidDocument
	case unsupportedVersion
	case tooLarge
	case invalidValue(String)
	case legacyRestore
	case stalePreview
	case busy

	var errorDescription: String? {
		switch self {
		case .invalidDocument: String(localized: .PreferencesTransfer.fileIsNotAValidConfigurationSnapshot)
		case .unsupportedVersion: String(localized: .PreferencesTransfer.configurationSnapshotUsesANewerFormat)
		case .tooLarge: String(localized: .PreferencesTransfer.configurationFileExceedsSizeLimit)
		case let .invalidValue(key): String(localized: .PreferencesTransfer.invalidValue(key))
		case .legacyRestore: String(localized: .PreferencesTransfer.legacyNotice)
		case .stalePreview: String(localized: .PreferencesTransfer.configurationChangedAfterPreview)
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
	var source = Source.localRecovery
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
			values = preferences
			unset = Set(absent)
			clientValue = root["clients"]
			let declared = Set(Preferences.allKeys.filter {
				!Preferences.isExcludedFromExport($0.name) && $0.name != Preferences.Connection.clientList.name
			}.map(\.name))
			guard declared.isSubset(of: Set(values.keys).union(unset)) else {
				throw PreferencesTransferError.invalidDocument
			}
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

/// The standard store is an explicit dependency, including in tests. No suite override
/// changes process-global UserDefaults.standard or the user's registration domain.
struct PreferencesTransferStores {
	let container: UserDefaults
	let containerDomain: String
	let standard: UserDefaults
	let standardDomain: String

	static var live: Self {
		Self(container: TextualUserDefaults.container, containerDomain: TextualUserDefaults.container.suiteName,
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

	func persistentDomain(for storage: PreferenceStorage) -> [String: Any] {
		switch storage {
		case .container: container.persistentDomain(forName: containerDomain) ?? [:]
		case .standard: standard.persistentDomain(forName: standardDomain) ?? [:]
		}
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

	/** Removes every persisted value a declaration would refuse, and reports
	 which keys lost one.

	 Bounds arrive after values do: a count or port stored before its range was
	 declared, or by an older build, reads back exactly as it was stored.
	 Everything downstream holds values to the declarations — the Settings
	 fields, an export, the recovery backup taken before an import, the import
	 plan itself — so one stale value would make all of them fail on this
	 Mac's own state. Removing it leaves the registered default in its place,
	 which is what the field would have refused it back to. Runs once at
	 launch, before anything reads. */
	@discardableResult
	func removeValuesDeclarationsRefuse() -> [String] {
		let persisted: [PreferenceStorage: [String: Any]] = [
			.container: persistentDomain(for: .container),
			.standard: persistentDomain(for: .standard),
		]
		var values: [String: PropertyListValue] = [:]
		var refused: [String] = []
		for key in Preferences.allKeys {
			guard let object = persisted[key.storage]?[key.name] else { continue }
			if let value = PropertyListValue(propertyList: object),
			   let coerced = Preferences.coerce(value, forKey: key.name)
			{
				values[key.name] = coerced
			} else {
				refused.append(key.name)
			}
		}
		// A value that is fine on its own can still contradict its partner.
		for key in Preferences.allKeys {
			if let value = values[key.name], !key.isValid(value, in: values) {
				refused.append(key.name)
			}
		}
		for name in refused {
			set(nil, for: UntypedPreferenceKey(name, storage: Preferences.storage(for: name)))
		}
		return refused
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
		for (storage, domain) in [(container, containerDomain), (standard, standardDomain)] {
			for (name, object) in storage.persistentDomain(forName: domain) ?? [:]
				where Preferences.key(named: name) == nil && !Preferences.isExcludedFromExport(name)
			{
				let key = UntypedPreferenceKey(name, storage: Preferences.storage(for: name))
				guard store(for: key) === storage else { continue }
				values[name] = PropertyListValue(propertyList: object)
			}
		}
		return PreferencesArchive(isComplete: true, values: values, unset: unset,
		                          clients: clients.map(PreferencesClientArchive.withoutPendingSecrets))
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

nonisolated struct PreferencesTransferPlan: Sendable { // nonisolated: value
	let before: PreferencesArchive
	let result: PreferencesArchive
	let changedKeys: [String]
	let removedKeys: [String]
	let addedClients: [String]
	let updatedClients: [String]
	let removedClients: [String]
	let mode: PreferencesTransferMode

	init(archive: PreferencesArchive, current: PreferencesArchive, mode: PreferencesTransferMode) throws {
		guard mode != .restore || archive.isComplete else { throw PreferencesTransferError.legacyRestore }
		before = current
		self.mode = mode
		var result = current
		if mode == .restore {
			result.values = archive.values
			result.unset = archive.unset
		} else {
			result.values.merge(archive.values) { _, imported in imported }
			for name in archive.unset {
				result.values.removeValue(forKey: name)
			}
			result.unset.formUnion(archive.unset)
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
		changedKeys = Set(current.values.keys).union(result.values.keys).filter {
			current.values[$0] != result.values[$0]
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
	}
}
