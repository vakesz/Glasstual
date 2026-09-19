// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

nonisolated enum SettingsTransferError: LocalizedError {
	case invalidDocument
	case unsupportedVersion
	case tooLarge
	case invalidValue(String)
	case stalePreview
	case connectionsDidNotClose
	case busy

	var errorDescription: String? {
		switch self {
		case .invalidDocument: String(localized: .SettingsTransfer.fileIsNotAValidConfigurationSnapshot)
		case .unsupportedVersion: String(localized: .SettingsTransfer.configurationSnapshotUsesANewerFormat)
		case .tooLarge: String(localized: .SettingsTransfer.configurationFileExceedsSizeLimit)
		case .invalidValue: String(localized: .SettingsTransfer.invalidValue)
		case .stalePreview: String(localized: .SettingsTransfer.configurationChangedAfterPreview)
		case .connectionsDidNotClose: String(localized: .SettingsTransfer.serversDidNotDisconnect)
		case .busy: String(localized: .SettingsTransfer.configurationTransferInProgress)
		}
	}
}

/** One configuration, as a file carries it.

 An effective value and a deliberately unset key are two different things, so
 the archive records both: `values` is what the source had, `unset` is what it
 had deliberately removed. */
nonisolated struct SettingsArchive: Equatable, Sendable {
	enum Source: Sendable {
		case portable, localRecovery
	}

	static let format = "GlasstualConfiguration"
	static let recoveryFormat = "GlasstualLocalRecovery"
	/** Version 1 of the format, and the only one there is a reader for.

	 A file written by any earlier release also claims version 1, and is refused
	 one step further in: every field of a stored connection is checked against
	 the names this build declares, so a key that no longer exists rejects the
	 whole document rather than being half applied. */
	static let version = 1
	static let maximumBytes = 16 * 1024 * 1024
	/// What an export is offered as, and what an import expects to be handed.
	static let defaultArchiveFilename = "GlasstualPreferences.plist"
	var values: [String: PropertyListValue]
	var unset: Set<String>
	var sessions: [ServerConfig]?
	var ignoredKeys: [String] = []
	/// Only this Mac's own snapshot, or a file read out of the protected
	/// recovery store, may claim local-recovery privileges; everything else is
	/// a file someone handed over.
	var source = Source.portable
	/// An omitted list preserves the target's commands; an included empty list clears them.
	var omittedConnectCommands: Set<String> = []

	func hasSameConfiguration(as other: Self) -> Bool {
		func configurations(_ sessions: [ServerConfig]?) -> [[String: PropertyListValue]]? {
			sessions?.map {
				var config = $0
				/* The last server timestamp moves on its own as messages
				 arrive; it is not something the user configured. */
				config.lastMessageServerTime = 0
				return config.dictionaryValue
			}
		}
		let ownConfigurations = configurations(sessions)
		let otherConfigurations = configurations(other.sessions)
		return values == other.values && unset == other.unset && ownConfigurations == otherConfigurations
	}

	func encoded(includeConnectCommands: Bool = false) throws -> Data {
		guard let sessions else { throw SettingsTransferError.invalidDocument }
		let configurations = sessions.map { session in
			SettingsSessionArchive.portableDictionary(
				session,
				includeConnectCommands: includeConnectCommands
					&& !omittedConnectCommands.contains(session.uniqueIdentifier)
			)
		}
		return try encode(configurations: configurations, format: Self.format)
	}

	/// Only the protected recovery store uses this encoder. Portable export always sanitizes again.
	func recoveryEncoded() throws -> Data {
		guard source == .localRecovery, omittedConnectCommands.isEmpty, let sessions else {
			throw SettingsTransferError.invalidDocument
		}
		return try encode(
			configurations: sessions.map { SettingsSessionArchive.withoutPendingSecrets($0).dictionaryValue },
			format: Self.recoveryFormat
		)
	}

	private func encode(configurations: [[String: PropertyListValue]], format: String) throws -> Data {
		guard let sessions else { throw SettingsTransferError.invalidDocument }
		guard sessions.count == configurations.count else { throw SettingsTransferError.invalidDocument }
		let dictionary: [String: PropertyListValue] = [
			"format": .string(format), "version": .integer(Self.version),
			"preferences": .dictionary(values), "unset": .init(unset.sorted()),
			"clients": .array(configurations.map(PropertyListValue.dictionary)),
		]
		let data = try PropertyListSerialization.data(
			fromPropertyList: dictionary.propertyListObject, format: .xml, options: 0
		)
		guard data.count <= Self.maximumBytes else { throw SettingsTransferError.tooLarge }
		return data
	}

	static func decode(_ data: Data, source: Source = .portable) throws -> Self {
		guard data.count <= maximumBytes else { throw SettingsTransferError.tooLarge }
		let object: Any
		do {
			object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
		} catch { throw SettingsTransferError.invalidDocument }
		var remainingNodes = 200_000
		try checkBounds(object, depth: 0, remaining: &remainingNodes)
		guard let root = [String: PropertyListValue](propertyList: object) else {
			throw SettingsTransferError.invalidDocument
		}
		let expectedFormat = source == .localRecovery ? recoveryFormat : format
		guard root["format"]?.string == expectedFormat else { throw SettingsTransferError.invalidDocument }
		guard root["version"] == .integer(version) else { throw SettingsTransferError.unsupportedVersion }
		guard let settings = root["preferences"]?.dictionary,
		      let absent = root["unset"]?.stringArray, Set(absent).count == absent.count,
		      Set(absent).isDisjoint(with: settings.keys), root["clients"]?.array != nil
		else { throw SettingsTransferError.invalidDocument }
		/* A declared key the file names in neither list was declared after the
		 file was written. The file says nothing about it: Merge leaves the
		 local value alone and Restore returns it to its registered default,
		 so every key added later keeps older exports and backups readable. */
		var values = settings
		var unset = Set(absent)
		let sessionValue = root["clients"]
		var ignored: [String] = []
		for key in Set(values.keys).union(unset) {
			if SettingsKeys.isExcludedFromExport(key) || key == SettingsKeys.Sessions.serverSessions.name {
				ignored.append(key)
				values.removeValue(forKey: key)
				unset.remove(key)
				continue
			}
			if let value = values[key] {
				guard let coerced = SettingsKeys.coerce(value, forKey: key) else {
					throw SettingsTransferError.invalidValue(key)
				}
				values[key] = coerced
			}
		}
		var sessions = try sessionValue.map(SettingsSessionArchive.decode)
		let omitted = Set((sessionValue?.array ?? []).compactMap { value -> String? in
			guard let dictionary = value.dictionary,
			      dictionary[ServerConfig.CodingKeys.loginCommands.rawValue] == nil else { return nil }
			return dictionary[ServerConfig.CodingKeys.uniqueIdentifier.rawValue]?.string
		})
		if source == .localRecovery {
			guard omitted.isEmpty else { throw SettingsTransferError.invalidDocument }
		} else {
			sessions = sessions?.map(SettingsSessionArchive.portable)
		}
		return Self(values: values, unset: unset, sessions: sessions, ignoredKeys: ignored.sorted(),
		            source: source, omittedConnectCommands: omitted)
	}

	private static func checkBounds(_ object: Any, depth: Int, remaining: inout Int) throws {
		guard depth <= 32, remaining > 0 else { throw SettingsTransferError.tooLarge }
		remaining -= 1
		if let number = object as? NSNumber, !number.doubleValue.isFinite {
			throw SettingsTransferError.invalidDocument
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
		guard attributes.isRegularFile == true else { throw SettingsTransferError.invalidDocument }
		guard let size = attributes.fileSize, size <= maximumBytes else { throw SettingsTransferError.tooLarge }
		let handle = try FileHandle(forReadingFrom: url)
		defer { try? handle.close() }
		let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
		guard data.count <= maximumBytes else { throw SettingsTransferError.tooLarge }
		return data
	}
}

nonisolated enum SettingsTransferMode: String, CaseIterable, Sendable {
	case merge
	case restore
}

extension SettingsArchive {
	/// Everything this Mac has stored that an export carries, as an archive.
	static func snapshot(from stores: SettingsStores, sessions: [ServerConfig]) -> SettingsArchive {
		var values: [String: PropertyListValue] = [:]
		var unset: Set<String> = []
		for key in SettingsKeys.allKeys where !SettingsKeys.isExcludedFromExport(key.name)
			&& key.name != SettingsKeys.Sessions.serverSessions.name
		{
			if let value = stores.store(for: key).object(forKey: key.name).flatMap(PropertyListValue.init(propertyList:))
				?? key.registeredDefault
			{
				values[key.name] = value
			} else {
				unset.insert(key.name)
			}
		}
		for storage in SettingStorage.allCases {
			for (name, object) in stores.persistentDomain(for: storage)
				where SettingsKeys.key(named: name) == nil && !SettingsKeys.isExcludedFromExport(name)
			{
				guard SettingsKeys.storage(for: name) == storage else { continue }
				values[name] = PropertyListValue(propertyList: object)
			}
		}
		return SettingsArchive(values: values, unset: unset,
		                       sessions: sessions.map(SettingsSessionArchive.withoutPendingSecrets),
		                       source: .localRecovery)
	}
}
