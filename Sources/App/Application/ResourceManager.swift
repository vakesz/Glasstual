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

public nonisolated enum ResourceDocumentType {
	public static let bundleFileExtension = ".bundle"
	public static let bundleFilenameExtension = "bundle"
	public static let scriptFileExtension = ".scpt"
	public static let scriptFilenameExtension = "scpt"
}

@objc(TPCResourceManager)
public final nonisolated class ResourceManager: NSObject {
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "ResourceManager"
	)

	/* ISOLATION-EXCEPTION: `NSCache` is documented as thread-safe but is not
	 `Sendable`, and this is a `let` bound once. */
	private nonisolated(unsafe) static let resourcesCache = NSCache<NSString, AnyObject>()

	public static var sharedResourcesCache: NSCache<NSString, AnyObject> {
		resourcesCache
	}

	@objc public static func copyResourcesToApplicationSupportFolder() {
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
		guard cacheValue else {
			return loadObject(fromResources: name, inDirectory: subpath, key: key)
		}

		let cacheKey = cacheKey(name: name, subpath: subpath, key: key) as NSString

		if let cachedValue = resourcesCache.object(forKey: cacheKey) {
			return cachedValue as? Value
		}

		guard let loadedValue: Value = loadObject(fromResources: name, inDirectory: subpath, key: key) else {
			return nil
		}

		resourcesCache.setObject(loadedValue as AnyObject, forKey: cacheKey)

		return loadedValue
	}

	public static func dictionary(
		fromResources name: String,
		inDirectory subpath: String? = nil,
		key: String? = nil,
		cacheValue: Bool = true
	) -> [String: Any]? {
		load(fromResources: name, inDirectory: subpath, key: key, cacheValue: cacheValue)
	}

	public static func array(
		fromResources name: String,
		inDirectory subpath: String? = nil,
		key: String? = nil,
		cacheValue: Bool = true
	) -> [Any]? {
		load(fromResources: name, inDirectory: subpath, key: key, cacheValue: cacheValue)
	}

	private static func loadObject<Value>(
		fromResources name: String,
		inDirectory subpath: String?,
		key: String?
	) -> Value? {
		guard let resourceURL = Bundle.main.url(forResource: name, withExtension: "plist", subdirectory: subpath) else {
			logger.error(
				"Resource '\(name, privacy: .public)' in subpath '\(subpath ?? "<No subpath>", privacy: .public)' was not found."
			)

			return nil
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
			guard let dictionary = propertyList as? [String: Any] else {
				logger.error(
					"Contents of resource '\(Self.displayPath(for: resourceURL), privacy: .public)' is not a dictionary. Cannot locate value of 'key' in other formats."
				)

				return nil
			}

			objectValue = dictionary[key]
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

	private static func cacheKey(name: String, subpath: String?, key: String?) -> String {
		"\(name).plist / \(subpath ?? "Root Folder") / \(key ?? "Root Object")"
	}

	private static func displayPath(for url: URL) -> String {
		url.standardizedTildePath ?? url.path
	}
}
