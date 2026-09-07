/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Plugin interface metadata")
struct PluginInterfaceMetadataTests {
	@Test("Legacy compatible 8.x markers remain loadable", arguments: ["8.0.0", "8.1.2", "8.99.0"])
	func compatibleLegacyMarkers(_ version: String) throws {
		try withBundle(minimum: version) { #expect(PluginManager.supportsCurrentPluginProtocol($0)) }
	}

	@Test(
		"Missing, obsolete and future legacy markers do not imply interface compatibility",
		arguments: [nil, "", "7.0.0", "9.0.0", "8.broken.0"]
	)
	func incompatibleLegacyMarkers(_ version: String?) throws {
		try withBundle(minimum: version) { #expect(PluginManager.supportsCurrentPluginProtocol($0) == false) }
	}

	@Test("Explicit interface metadata takes precedence over the legacy marker")
	func explicitVersionWins() throws {
		try withBundle(interface: .integer(1)) { #expect(PluginManager.supportsCurrentPluginProtocol($0)) }
		for invalid in [PropertyListValue.integer(2), .integer(0), .boolean(true), .string("1"), .double(1.5)] {
			try withBundle(interface: invalid, minimum: "8.0.0") {
				#expect(PluginManager.supportsCurrentPluginProtocol($0) == false)
			}
		}
	}

	@Test("An unsigned staged plugin cannot replace an installed copy")
	func failedPluginValidationPreservesInstalledCopy() async throws {
		let manager = FileManager.default
		let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		let source = root.appendingPathComponent("source.bundle", isDirectory: true)
		let destination = root.appendingPathComponent("installed.bundle", isDirectory: true)
		let contents = source.appendingPathComponent("Contents", isDirectory: true)
		let executable = contents.appendingPathComponent("MacOS/Plugin")
		try manager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
		try manager.createDirectory(at: destination, withIntermediateDirectories: true)
		defer { try? manager.removeItem(at: root) }
		let info: [String: PropertyListValue] = [
			"CFBundleIdentifier": .string("test.\(UUID().uuidString)"),
			"CFBundleExecutable": .string("Plugin"),
			"CFBundlePackageType": .string("BNDL"),
			"NSPrincipalClass": .string("NSObject"),
			PluginManager.interfaceVersionMetadataKey: .integer(1),
		]
		let data = try PropertyListSerialization.data(
			fromPropertyList: info.propertyListObject,
			format: .xml,
			options: 0
		)
		try data.write(to: contents.appendingPathComponent("Info.plist"))
		try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
		try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
		try Data("working".utf8).write(to: destination.appendingPathComponent("old"))
		await #expect(throws: (any Error).self) {
			try await ResourceFileImporter.installPlugin(source, into: destination)
		}
		#expect(try Data(contentsOf: destination.appendingPathComponent("old")) == Data("working".utf8))
		#expect(manager.fileExists(atPath: executable.path))
		#expect(try manager.contentsOfDirectory(atPath: root.path).sorted() == ["installed.bundle", "source.bundle"])
	}

	private func withBundle(
		interface: PropertyListValue? = nil,
		minimum: String? = nil,
		body: (Bundle) throws -> Void
	) throws {
		let root = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).bundle")
		let contents = root.appendingPathComponent("Contents", isDirectory: true)
		try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		var info: [String: PropertyListValue] = [
			"CFBundleIdentifier": .string("test.\(UUID().uuidString)"),
			"CFBundlePackageType": .string("BNDL"),
		]
		info[PluginManager.interfaceVersionMetadataKey] = interface
		info["MinimumGlasstualVersion"] = minimum.map(PropertyListValue.string)
		let data = try PropertyListSerialization.data(
			fromPropertyList: info.propertyListObject,
			format: .xml,
			options: 0
		)
		try data.write(to: contents.appendingPathComponent("Info.plist"))
		try body(#require(Bundle(url: root)))
	}
}
