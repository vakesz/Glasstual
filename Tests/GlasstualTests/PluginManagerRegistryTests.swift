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
	@Test("A late scan cannot overwrite a newer catalog or republish after unload")
	func refreshGenerationRejectsStaleResults() throws {
		let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		let url = root.appendingPathComponent("Fresh.SCPT")
		try Data().write(to: url)
		let script = try #require(PluginScript(url: url, origin: .custom))
		let manager = PluginManager()
		let first = manager.reserveScriptGeneration()
		let second = manager.reserveScriptGeneration()
		let fresh = PluginScriptCatalog(commandsByName: ["fresh": script], customScriptsURL: root)
		manager.publishScriptCatalog(fresh, generation: second)
		manager.publishScriptCatalog(PluginScriptCatalog(), generation: first)
		#expect(manager.supportedAppleScriptCommands == ["fresh"])
		#expect(manager.handler(forOutgoingCommand: "FRESH") == .script(path: url.path))
		#expect(manager.script(at: url) == script)
		manager.unloadPlugins()
		let third = manager.reserveScriptGeneration()
		manager.publishScriptCatalog(fresh, generation: third)
		#expect(manager.supportedAppleScriptCommands.isEmpty)
	}

	@Test("Unloading an independent manager does not unload the application's plugins")
	func pluginObjectsBelongToTheirManager() throws {
		let shared = SharedApplication.sharedPluginManager()
		let original = try #require(shared.loadedPlugins)
		#expect(original.isEmpty == false)
		let independent = PluginManager()
		independent.unloadPlugins()
		#expect(shared.loadedPlugins?.map(ObjectIdentifier.init) == original.map(ObjectIdentifier.init))
		#expect(shared.pluginsWithPreferencePanes.allSatisfy {
			$0.preferencePaneIdentifier == $0.bundle.bundleIdentifier
		})
	}

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
