/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

private let bundledPluginCount = 6

@MainActor
@Suite("Bundled plugin registry")
struct PluginManagerRegistryTests {
	@Test("Every bundled plugin principal has finished loading before the tests start")
	func allBundledPluginPrincipalsFinishLoadingBeforeTestsStart() throws {
		let manager = SharedApplication.sharedPluginManager()

		let bundleURLs = try FileManager.default.contentsOfDirectory(
			at: PathInfo.bundledExtensionsURL,
			includingPropertiesForKeys: nil
		).filter { $0.pathExtension == ResourceDocumentType.bundleFilenameExtension }

		#expect(bundleURLs.count == bundledPluginCount)

		let bundles = try bundleURLs.map { try #require(Bundle(url: $0)) }
		let loadedPlugins = try #require(manager.loadedPlugins)

		for bundle in bundles {
			let bundleIdentifier = try #require(bundle.bundleIdentifier)
			let plugin = try #require(
				loadedPlugins.first { $0.bundle.bundleIdentifier == bundleIdentifier },
				"Bundled plugin did not finish loading: \(bundle.bundlePath)"
			)
			let expectedPrincipalClass: AnyClass = try #require(bundle.principalClass)
			let principal = try #require(plugin.primaryClass as? NSObject)

			#expect(principal.isKind(of: expectedPrincipalClass), "\(bundleIdentifier)")
		}
	}

	@Test("Bundled script commands are ready before command entry")
	func bundledScriptCommandsAreCachedAtLaunch() {
		let paths = SharedApplication.sharedPluginManager().supportedAppleScriptCommandsAndPaths

		#expect(Set(paths.keys).isSuperset(of: ["date", "moti"]))
		#expect(paths["date"]?.hasSuffix("/Bundled Scripts/date.scpt") == true)
		#expect(paths["moti"]?.hasSuffix("/Bundled Scripts/moti.scpt") == true)
	}
}
