/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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

	private nonisolated(unsafe) static let resourcesCache = NSCache<AnyObject, AnyObject>()

	@objc public static var sharedResourcesCache: NSCache<AnyObject, AnyObject> {
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

	// MARK: - Dictionaries

	@objc(dictionaryFromResources:)
	public static func dictionary(fromResources name: String) -> [String: Any]? {
		dictionary(fromResources: name, inDirectory: nil, key: nil, cacheValue: true)
	}

	@objc(dictionaryFromResources:cacheValue:)
	public static func dictionary(fromResources name: String, cacheValue: Bool) -> [String: Any]? {
		dictionary(fromResources: name, inDirectory: nil, key: nil, cacheValue: cacheValue)
	}

	@objc(dictionaryFromResources:inDirectory:)
	public static func dictionary(fromResources name: String, inDirectory subpath: String?) -> [String: Any]? {
		dictionary(fromResources: name, inDirectory: subpath, key: nil, cacheValue: true)
	}

	@objc(dictionaryFromResources:inDirectory:cacheValue:)
	public static func dictionary(
		fromResources name: String,
		inDirectory subpath: String?,
		cacheValue: Bool
	) -> [String: Any]? {
		dictionary(fromResources: name, inDirectory: subpath, key: nil, cacheValue: cacheValue)
	}

	@objc(dictionaryFromResources:key:)
	public static func dictionary(fromResources name: String, key: String?) -> [String: Any]? {
		dictionary(fromResources: name, inDirectory: nil, key: key, cacheValue: true)
	}

	@objc(dictionaryFromResources:key:cacheValue:)
	public static func dictionary(fromResources name: String, key: String?, cacheValue: Bool) -> [String: Any]? {
		dictionary(fromResources: name, inDirectory: nil, key: key, cacheValue: cacheValue)
	}

	@objc(dictionaryFromResources:inDirectory:key:)
	public static func dictionary(
		fromResources name: String,
		inDirectory subpath: String?,
		key: String?
	) -> [String: Any]? {
		dictionary(fromResources: name, inDirectory: subpath, key: key, cacheValue: true)
	}

	@objc(dictionaryFromResources:inDirectory:key:cacheValue:)
	public static func dictionary(
		fromResources name: String,
		inDirectory subpath: String?,
		key: String?,
		cacheValue: Bool
	) -> [String: Any]? {
		object(fromResources: name, inDirectory: subpath, key: key, kindOf: NSDictionary.self, cacheValue: cacheValue)
			as? [String: Any]
	}

	// MARK: - Arrays

	@objc(arrayFromResources:)
	public static func array(fromResources name: String) -> [Any]? {
		array(fromResources: name, inDirectory: nil, key: nil, cacheValue: true)
	}

	@objc(arrayFromResources:cacheValue:)
	public static func array(fromResources name: String, cacheValue: Bool) -> [Any]? {
		array(fromResources: name, inDirectory: nil, key: nil, cacheValue: cacheValue)
	}

	@objc(arrayFromResources:inDirectory:)
	public static func array(fromResources name: String, inDirectory subpath: String?) -> [Any]? {
		array(fromResources: name, inDirectory: subpath, key: nil, cacheValue: true)
	}

	@objc(arrayFromResources:inDirectory:cacheValue:)
	public static func array(fromResources name: String, inDirectory subpath: String?, cacheValue: Bool) -> [Any]? {
		array(fromResources: name, inDirectory: subpath, key: nil, cacheValue: cacheValue)
	}

	@objc(arrayFromResources:key:)
	public static func array(fromResources name: String, key: String?) -> [Any]? {
		array(fromResources: name, inDirectory: nil, key: key, cacheValue: true)
	}

	@objc(arrayFromResources:key:cacheValue:)
	public static func array(fromResources name: String, key: String?, cacheValue: Bool) -> [Any]? {
		array(fromResources: name, inDirectory: nil, key: key, cacheValue: cacheValue)
	}

	@objc(arrayFromResources:inDirectory:key:)
	public static func array(fromResources name: String, inDirectory subpath: String?, key: String?) -> [Any]? {
		array(fromResources: name, inDirectory: subpath, key: key, cacheValue: true)
	}

	@objc(arrayFromResources:inDirectory:key:cacheValue:)
	public static func array(
		fromResources name: String,
		inDirectory subpath: String?,
		key: String?,
		cacheValue: Bool
	) -> [Any]? {
		object(fromResources: name, inDirectory: subpath, key: key, kindOf: NSArray.self, cacheValue: cacheValue)
			as? [Any]
	}

	// MARK: - Generic object loading

	@objc(objectFromResources:inDirectory:key:kindOf:cacheValue:)
	public static func object(
		fromResources name: String,
		inDirectory subpath: String?,
		key: String?,
		kindOf type: AnyClass,
		cacheValue: Bool
	) -> Any? {
		if cacheValue == false {
			return loadObject(fromResources: name, inDirectory: subpath, key: key, kindOf: type)
		}

		let cacheKey = cacheKey(name: name, subpath: subpath, key: key) as NSString

		if let cachedValue = resourcesCache.object(forKey: cacheKey) {
			return cachedValue
		}

		guard let loadedValue = loadObject(fromResources: name, inDirectory: subpath, key: key, kindOf: type) else {
			return nil
		}

		resourcesCache.setObject(loadedValue as AnyObject, forKey: cacheKey as AnyObject)

		return loadedValue
	}

	private static func loadObject(
		fromResources name: String,
		inDirectory subpath: String?,
		key: String?,
		kindOf type: AnyClass
	) -> Any? {
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

		guard let objectValue, (objectValue as AnyObject).isKind(of: type) else {
			logger.error(
				"Contents of key '\(key ?? "<Root Object>", privacy: .public)' in resource '\(Self.displayPath(for: resourceURL), privacy: .public)' is not kind of class: \(NSStringFromClass(type), privacy: .public)"
			)

			return nil
		}

		return objectValue
	}

	private static func cacheKey(name: String, subpath: String?, key: String?) -> String {
		"\(name).plist / \(subpath ?? "Root Folder") / \(key ?? "Root Object")"
	}

	private static func displayPath(for url: URL) -> String {
		(url as NSURL).textualStandardizedTildePath ?? url.path
	}
}
