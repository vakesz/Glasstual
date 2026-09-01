/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/// Interface Builder resources reintroduce stringly typed classes, outlets,
/// actions and bindings. All application and first-party plugin views are now
/// constructed in Swift or SwiftUI, so keep that architectural boundary
/// explicit instead of retaining runtime-name tests for resources that no
/// longer exist.
@Suite("SwiftUI resource migration")
struct SwiftUIResourceMigrationTests {
	private static func files(withExtension pathExtension: String, below root: URL) -> [URL] {
		guard let enumerator = FileManager.default.enumerator(
			at: root,
			includingPropertiesForKeys: nil,
			options: [.skipsHiddenFiles]
		) else {
			return []
		}

		return enumerator
			.compactMap { $0 as? URL }
			.filter { $0.pathExtension == pathExtension }
			.sorted { $0.path < $1.path }
	}

	@Test("The source tree contains no Interface Builder documents")
	func sourceTreeContainsNoInterfaceBuilderDocuments() {
		let sources = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appending(path: "Sources")

		let documents = Self.files(withExtension: "xib", below: sources)

		#expect(documents.isEmpty, "Interface Builder documents found: \(documents.map(\.path))")
	}

	@Test("The application bundle contains no compiled Interface Builder resources")
	func applicationBundleContainsNoCompiledInterfaceBuilderResources() throws {
		let resources = try #require(Bundle.main.resourceURL)
		let nibs = Self.files(withExtension: "nib", below: resources)

		#expect(nibs.isEmpty, "Compiled Interface Builder resources found: \(nibs.map(\.path))")
	}
}
