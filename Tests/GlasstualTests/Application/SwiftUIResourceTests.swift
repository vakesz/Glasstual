// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// Interface Builder resources reintroduce stringly typed classes, outlets,
/// actions and bindings. Every application view is now
/// constructed in Swift or SwiftUI, so keep that architectural boundary
/// explicit instead of retaining runtime-name tests for resources that no
/// longer exist.
@Suite("SwiftUI resource migration")
struct SwiftUIResourceTests {
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

	/** Both helpers exist because the three gates below assert that a walk found
	 nothing, so each one first has to show that the walk happened at all:
	 `enumerator(at:)` answers `nil` for a directory that has moved, and a
	 directory that is not there any more is exactly the kind of path that goes
	 stale silently. */
	private static func containsAnyFile(below root: URL) -> Bool {
		guard let enumerator = FileManager.default.enumerator(
			at: root,
			includingPropertiesForKeys: nil,
			options: [.skipsHiddenFiles]
		) else {
			return false
		}

		return enumerator.nextObject() != nil
	}

	private static func directory(_ relativePath: String) throws -> URL {
		let url = RepositoryPaths.root.appending(path: relativePath)

		try #require(
			FileManager.default.fileExists(atPath: url.path),
			"\(url.path) is not where this test looks for it"
		)

		return url
	}

	@Test("The source tree contains no Interface Builder documents")
	func sourceTreeContainsNoInterfaceBuilderDocuments() throws {
		let sources = try Self.directory("Sources")

		#expect(Self.files(withExtension: "swift", below: sources).isEmpty == false)

		let documents = Self.files(withExtension: "xib", below: sources)

		#expect(documents.isEmpty, "Interface Builder documents found: \(documents.map(\.path))")
	}

	@Test("The application bundle contains no compiled Interface Builder resources")
	func applicationBundleContainsNoCompiledInterfaceBuilderResources() throws {
		let resources = try #require(Bundle.main.resourceURL)

		#expect(Self.containsAnyFile(below: resources), "\(resources.path) held nothing to audit")

		let nibs = Self.files(withExtension: "nib", below: resources)

		#expect(nibs.isEmpty, "Compiled Interface Builder resources found: \(nibs.map(\.path))")
	}

	/// Native lists own reuse, selection and keyboard behavior in three features.
	/// Their complete inventory is checked alongside the unchanged prohibition
	/// on Interface Builder outlets and migrated button controls.
	@Test("Native list adapters stay in their owning features without migrated buttons or outlets")
	func nativeListAdapterInventory() throws {
		let appSources = try Self.directory("Sources/App")
		let swiftFiles = Self.files(withExtension: "swift", below: appSources)
		let bannedTokens = ["@IBOutlet", "NSButton"]
		let approvedListSources: [String: Set<String>] = [
			"NSOutlineView": [
				"Features/Sidebar/SidebarOutlineTree.swift",
				"Features/Sidebar/SidebarOutlineView.swift",
			],
			"NSTableView": [
				"Features/MemberList/MemberListTable.swift",
				"Features/MemberList/MemberListTableCommands.swift",
				"Features/ServerChannelList/ServerChannelListTable.swift",
			],
		]
		var nativeListSources = approvedListSources.mapValues { _ in Set<String>() }
		var offenders: [String] = []

		#expect(swiftFiles.isEmpty == false, "\(appSources.path) held no Swift to audit")

		for file in swiftFiles {
			let contents = try String(contentsOf: file, encoding: .utf8)
			let relativePath = file.path.replacingOccurrences(of: appSources.path + "/", with: "")
			for token in approvedListSources.keys where contents.contains(token) {
				nativeListSources[token, default: []].insert(relativePath)
			}
			for line in contents.split(separator: "\n") where bannedTokens.contains(where: line.contains) {
				offenders.append("\(file.lastPathComponent): \(line.trimmingCharacters(in: .whitespaces))")
			}
		}

		#expect(nativeListSources == approvedListSources)
		#expect(offenders.isEmpty, "Migrated AppKit controls or outlets found: \(offenders)")
	}
}
