/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation
import os

/// The result of scanning the extension folders, expressed as file URLs so the
/// scan can run off the main actor and hand its findings back.
nonisolated struct PluginDiscovery: Sendable { // nonisolated: value
	var loadable: [URL] = []
	var obsolete: [URL] = []
	var rejected: [URL] = []
	var scriptCatalog = PluginScriptCatalog()
	var scriptGeneration: UInt64 = 0

	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "PluginManager"
	)

	/** Scans `searchPaths` in order, off the main actor.

	 Reading the folders and checking each bundle's code signature is slow, and
	 it used to run on the main actor at launch: the task that called it
	 inherited the main actor, and a synchronous function does not leave it.
	 A bundle identifier found again in a later folder is skipped, so an
	 installed copy cannot shadow the bundled one. */
	@concurrent
	static func scan(searchPaths: [String] = defaultSearchPaths) async -> PluginDiscovery {
		var discovery = PluginDiscovery()
		var seenBundleIdentifiers = Set<String>()

		for bundle in candidateBundles(in: searchPaths) {
			guard let bundleIdentifier = bundle.bundleIdentifier else {
				logger.error(
					"Refusing to load the bundle at “\(bundle.bundlePath, privacy: .public)“ because it declares no bundle identifier"
				)
				continue
			}

			guard seenBundleIdentifiers.insert(bundleIdentifier).inserted else {
				logger.info(
					"Skipping the bundle at “\(bundle.bundlePath, privacy: .public)“ because a bundle with the identifier “\(bundleIdentifier, privacy: .public)“ was already found at an earlier location"
				)
				continue
			}

			guard PluginBundleValidation.supportsCurrentPluginProtocol(bundle) else {
				discovery.obsolete.append(bundle.bundleURL)
				continue
			}

			guard PluginBundleValidation.isBundledExtension(bundle)
				|| PluginBundleValidation.isSignedByThisApplication(bundle)
			else {
				discovery.rejected.append(bundle.bundleURL)
				continue
			}

			discovery.loadable.append(bundle.bundleURL)
		}

		return discovery
	}

	/// The bundled extensions first, then the user's own folder when it exists.
	static var defaultSearchPaths: [String] {
		[PathInfo.bundledExtensions] + [PathInfo.customExtensions].compactMap(\.self)
	}

	private static func candidateBundles(in searchPaths: [String]) -> [Bundle] {
		searchPaths.flatMap { path -> [Bundle] in
			guard let filenames = try? FileManager.default.contentsOfDirectory(atPath: path) else {
				return []
			}

			return filenames.sorted().compactMap { filename in
				guard filename.hasSuffix(ResourceDocumentType.bundleFileExtension) else {
					return nil
				}

				let bundleURL = URL(fileURLWithPath: path, isDirectory: true)
					.appendingPathComponent(filename, isDirectory: true)

				return Bundle(url: bundleURL)
			}
		}
	}
}
