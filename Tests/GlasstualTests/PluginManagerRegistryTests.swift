/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import XCTest

private let bundledPluginCount = 6

@MainActor
final class PluginManagerRegistryTests: XCTestCase {
	func testAllBundledPluginPrincipalsFinishLoadingBeforeTestsStart() throws {
		let manager = SharedApplication.sharedPluginManager()

		let bundleURLs = try FileManager.default.contentsOfDirectory(
			at: PathInfo.bundledExtensionsURL,
			includingPropertiesForKeys: nil
		).filter { $0.pathExtension == ResourceDocumentType.bundleFilenameExtension }

		XCTAssertEqual(bundleURLs.count, bundledPluginCount)

		let bundles = try bundleURLs.map { try XCTUnwrap(Bundle(url: $0)) }
		let loadedPlugins = try XCTUnwrap(manager.loadedPlugins)

		for bundle in bundles {
			let bundleIdentifier = try XCTUnwrap(bundle.bundleIdentifier)
			let plugin = try XCTUnwrap(
				loadedPlugins.first { $0.bundle.bundleIdentifier == bundleIdentifier },
				"Bundled plugin did not finish loading: \(bundle.bundlePath)"
			)
			let expectedPrincipalClass: AnyClass = try XCTUnwrap(bundle.principalClass)
			let principal = try XCTUnwrap(plugin.primaryClass as? NSObject)

			XCTAssertTrue(principal.isKind(of: expectedPrincipalClass), bundleIdentifier)
		}
	}
}
