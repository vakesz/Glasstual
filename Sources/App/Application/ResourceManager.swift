/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation
import os
import Synchronization

public nonisolated enum ResourceDocumentType { // nonisolated: value
	public static let bundleFileExtension = ".bundle"
	public static let bundleFilenameExtension = "bundle"
	public static let scriptFileExtension = ".scpt"
	public static let scriptFilenameExtension = "scpt"
}

public final nonisolated class ResourceManager: NSObject { // nonisolated: value
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "ResourceManager"
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
	public static func removeAllCachedResources() {
		resourceFileContents.withLock { contents in
			contents.removeAll()
		}
	}

	/// Whether `name`'s contents have been read already. For tests: the cache is
	/// an optimisation, so nothing else has a reason to ask.
	public static func hasCachedResource(named name: String, inDirectory subpath: String? = nil) -> Bool {
		resourceFileContents.withLock { contents in
			contents[cacheKey(name: name, subpath: subpath)] != nil
		}
	}

	public static func copyResourcesToApplicationSupportFolder() {
		guard let sourcePath = PathInfo.customScripts,
		      let destinationRoot = PathInfo.groupContainerApplicationSupport
		else {
			return
		}

		let destinationPath = (destinationRoot as NSString).appendingPathComponent("/Custom Scripts/")
		let fileManager = FileManager.default

		guard fileManager.fileExists(atPath: sourcePath),
		      fileManager.fileExists(atPath: destinationPath) == false
		else {
			return
		}

		try? fileManager.createSymbolicLink(atPath: destinationPath, withDestinationPath: sourcePath)
	}

	// MARK: - Loading

	/// Reads `name`.plist from the bundle and returns `key`'s value, or the
	/// whole property list when `key` is nil, as `Value`.
	///
	/// This replaced sixteen overloads that existed only to spell out these
	/// defaults for Objective-C, and a `kindOf: AnyClass` runtime check.
	public static func load<Value>(
		_: Value.Type = Value.self,
		fromResources name: String,
		inDirectory subpath: String? = nil,
		key: String? = nil,
		cacheValue: Bool = true
	) -> Value? {
		loadObject(fromResources: name, inDirectory: subpath, key: key, cacheContents: cacheValue)
	}

	public static func dictionary(
		fromResources name: String,
		inDirectory subpath: String? = nil,
		key: String? = nil,
		cacheValue: Bool = true
	) -> [String: PropertyListValue]? {
		load(Any.self, fromResources: name, inDirectory: subpath, key: key, cacheValue: cacheValue)
			.flatMap { [String: PropertyListValue](propertyList: $0) }
	}

	public static func array(
		fromResources name: String,
		inDirectory subpath: String? = nil,
		key: String? = nil,
		cacheValue: Bool = true
	) -> [PropertyListValue]? {
		load(Any.self, fromResources: name, inDirectory: subpath, key: key, cacheValue: cacheValue)
			.flatMap { [PropertyListValue](propertyList: $0) }
	}

	private static func loadObject<Value>(
		fromResources name: String,
		inDirectory subpath: String?,
		key: String?,
		cacheContents: Bool
	) -> Value? {
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

		let propertyList: Any

		do {
			propertyList = try PropertyListSerialization.propertyList(from: fileContents, options: [], format: nil)
		} catch {
			logger.fault(
				"Resource '\(Self.displayPath(for: resourceURL), privacy: .public)' could not be parsed as a property list with error: \(error.localizedDescription, privacy: .public)"
			)

			return nil
		}

		let objectValue: Any?

		if let key {
			guard let dictionary = [String: PropertyListValue](propertyList: propertyList) else {
				logger.error(
					"Contents of resource '\(Self.displayPath(for: resourceURL), privacy: .public)' is not a dictionary. Cannot locate value of 'key' in other formats."
				)

				return nil
			}

			objectValue = dictionary[key]?.propertyListObject
		} else {
			objectValue = propertyList
		}

		guard let typedValue = objectValue as? Value else {
			logger.error(
				"Contents of key '\(key ?? "<Root Object>", privacy: .public)' in resource '\(Self.displayPath(for: resourceURL), privacy: .public)' is not a \(String(describing: Value.self), privacy: .public)"
			)

			return nil
		}

		return typedValue
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
