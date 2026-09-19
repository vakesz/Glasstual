// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os
import Synchronization

/// The filename extension an installable script carries.
nonisolated enum ResourceDocumentKind {
	static let scriptFilenameExtension = "scpt"
}

/// The bundled property list of fixed word lists, and the keys read from it.
nonisolated enum StaticStoreResource {
	static let name = "StaticStore"
	static let spellingIgnoresKey = "Spelling Ignores"
	static let forbiddenScriptCommandsKey = "Forbidden Script Commands"
	static let nickServNeedsIdentificationTokensKey = "NickServ Needs Identification Tokens"
	static let nickServIdentifiedTokensKey = "NickServ Identified Tokens"
}

/// Reading the property lists the application bundle ships with.
nonisolated enum BundleResources {
	private static let logger = Logger(
		subsystem: LogSubsystem.current,
		category: "BundleResources"
	)

	/// The bundled property lists this process has already read, as the bytes
	/// they were read from.
	///
	/// It was an `NSCache` of parsed objects, which is thread-safe but not
	/// `Sendable` and so needed an escape hatch to be a global. Caching the file
	/// contents instead keeps the point of the cache — none of these files is
	/// read from disk twice — around a value the compiler can check.
	private static let resourceFileContents = Mutex<[String: Data]>([:])

	/// Empties the cache. Tests plant entries in it, and it is process-wide.
	static func removeAllCachedResources() {
		resourceFileContents.withLock { contents in
			contents.removeAll()
		}
	}

	/// Whether `name`'s contents have been read already. For tests: the cache is
	/// an optimisation, so nothing else has a reason to ask.
	static func hasCachedResource(named name: String, inDirectory subpath: String? = nil) -> Bool {
		resourceFileContents.withLock { contents in
			contents[cacheKey(name: name, subpath: subpath)] != nil
		}
	}

	// MARK: - Loading

	static func dictionary(
		fromResources name: String,
		inDirectory subpath: String? = nil,
		key: String? = nil,
		cacheValue: Bool = true
	) -> [String: PropertyListValue]? {
		propertyList(fromResources: name, inDirectory: subpath, key: key, cacheContents: cacheValue)
			.flatMap { [String: PropertyListValue](propertyList: $0) }
	}

	static func array(
		fromResources name: String,
		inDirectory subpath: String? = nil,
		key: String? = nil,
		cacheValue: Bool = true
	) -> [PropertyListValue]? {
		propertyList(fromResources: name, inDirectory: subpath, key: key, cacheContents: cacheValue)
			.flatMap { [PropertyListValue](propertyList: $0) }
	}

	/// Reads `name`.plist from the bundle and answers `key`'s value, or the
	/// whole property list when `key` is nil. The two typed readers above are
	/// the interface; this is how they read.
	private static func propertyList(
		fromResources name: String,
		inDirectory subpath: String?,
		key: String?,
		cacheContents: Bool
	) -> Any? {
		guard let resourceURL = Bundle.main.url(forResource: name, withExtension: "plist", subdirectory: subpath) else {
			logger.error(
				"Resource '\(name, privacy: .public)' in subpath '\(subpath ?? "<No subpath>", privacy: .public)' was not found."
			)

			return nil
		}

		guard let fileContents = fileContents(of: resourceURL, name: name, subpath: subpath, cache: cacheContents)
		else {
			return nil
		}

		let rootObject: Any

		do {
			rootObject = try PropertyListSerialization.propertyList(from: fileContents, options: [], format: nil)
		} catch {
			logger.fault(
				"Resource '\(Self.displayPath(for: resourceURL), privacy: .public)' could not be parsed as a property list with error: \(error.localizedDescription, privacy: .public)"
			)

			return nil
		}

		guard let key else {
			return rootObject
		}

		guard let dictionary = [String: PropertyListValue](propertyList: rootObject) else {
			logger.error(
				"Contents of resource '\(Self.displayPath(for: resourceURL), privacy: .public)' is not a dictionary. Cannot locate value of 'key' in other formats."
			)

			return nil
		}

		return dictionary[key]?.propertyListObject
	}

	private static func fileContents(
		of resourceURL: URL,
		name: String,
		subpath: String?,
		cache: Bool
	) -> Data? {
		let cacheKey = cacheKey(name: name, subpath: subpath)

		if cache, let cached = resourceFileContents.withLock({ $0[cacheKey] }) {
			return cached
		}

		let fileContents: Data

		do {
			fileContents = try Data(contentsOf: resourceURL)
		} catch {
			logger.error(
				"Resource '\(Self.displayPath(for: resourceURL), privacy: .public)' could not be read with error: \(error.localizedDescription, privacy: .public)"
			)

			return nil
		}

		if cache {
			resourceFileContents.withLock { contents in
				contents[cacheKey] = fileContents
			}
		}

		return fileContents
	}

	private static func cacheKey(name: String, subpath: String?) -> String {
		"\(name).plist / \(subpath ?? "Root Folder")"
	}

	private static func displayPath(for url: URL) -> String {
		url.standardizedTildePath ?? url.path
	}
}
