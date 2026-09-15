/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Plugin discovery", .timeLimit(.minutes(1)))
struct PluginDiscoveryTests {
	/// The bundled plugins sit inside the application, so they load without a
	/// signature check of their own.
	@Test("Every bundled plugin is found loadable")
	func bundledPluginsAreLoadable() async throws {
		let bundled = try FileManager.default.contentsOfDirectory(
			at: PathInfo.bundledExtensionsURL,
			includingPropertiesForKeys: nil
		).filter { $0.pathExtension == ResourceDocumentType.bundleFilenameExtension }

		let discovery = await PluginDiscovery.scan(searchPaths: [PathInfo.bundledExtensions])

		#expect(bundled.isEmpty == false)
		#expect(Set(discovery.loadable.map(\.lastPathComponent)) == Set(bundled.map(\.lastPathComponent)))
		#expect(discovery.rejected.isEmpty)
		#expect(discovery.obsolete.isEmpty)
	}

	/** An installed bundle is sorted into what loads, what speaks an old
	 interface and what nobody signed; a bundle identifier seen in an earlier
	 folder shadows a later copy, and anything that is not a bundle is ignored. */
	@Test("Installed bundles are sorted by interface, signature and identity")
	func installedBundlesAreClassified() async throws {
		let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
		let first = root.appending(path: "first", directoryHint: .isDirectory)
		let second = root.appending(path: "second", directoryHint: .isDirectory)
		defer { try? FileManager.default.removeItem(at: root) }

		let sharedIdentifier = "test.\(UUID().uuidString)"
		let unsigned = try Self.makeBundle(
			named: "Unsigned",
			in: first,
			identifier: sharedIdentifier,
			interface: .integer(1)
		)
		let obsolete = try Self.makeBundle(named: "Obsolete", in: first, identifier: "test.\(UUID().uuidString)")
		let shadowed = try Self.makeBundle(
			named: "Shadowed",
			in: second,
			identifier: sharedIdentifier,
			interface: .integer(1)
		)
		try Data().write(to: second.appending(path: "notes.txt"))

		let discovery = await PluginDiscovery.scan(searchPaths: [first.path, second.path])

		#expect(discovery.loadable.isEmpty)
		#expect(discovery.rejected.map(\.lastPathComponent) == [unsigned.lastPathComponent])
		#expect(discovery.obsolete.map(\.lastPathComponent) == [obsolete.lastPathComponent])
		#expect(discovery.rejected.contains { $0.lastPathComponent == shadowed.lastPathComponent } == false)
	}

	private static func makeBundle(
		named name: String,
		in directory: URL,
		identifier: String,
		interface: PropertyListValue? = nil
	) throws -> URL {
		let bundle = directory.appending(path: "\(name).bundle", directoryHint: .isDirectory)
		let contents = bundle.appending(path: "Contents", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
		var info: [String: PropertyListValue] = [
			"CFBundleIdentifier": .string(identifier),
			"CFBundlePackageType": .string("BNDL"),
		]
		info[PluginBundleValidation.interfaceVersionMetadataKey] = interface
		let data = try PropertyListSerialization.data(
			fromPropertyList: info.propertyListObject,
			format: .xml,
			options: 0
		)
		try data.write(to: contents.appending(path: "Info.plist"))
		return bundle
	}
}
