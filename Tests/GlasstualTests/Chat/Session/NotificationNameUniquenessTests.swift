// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// One notification name per event: a duplicate raw string means two
/// declarations that can drift, and an inline literal means a name nobody can
/// find by searching for the constant.
@MainActor
@Suite("Notification name uniqueness")
struct NotificationNameUniquenessTests {
	/// The wire protocol and the chat domain built on it: both halves of what
	/// used to be one folder, so a name moved between them is still counted once.
	private static let moduleDirectories = ["Sources/App/Protocol", "Sources/App/Chat"]

	private static func moduleSources() -> [URL]? {
		let root = RepositoryPaths.root
		var sources: [URL] = []

		for moduleDirectory in moduleDirectories {
			guard let enumerator = FileManager.default.enumerator(
				at: root.appending(path: moduleDirectory),
				includingPropertiesForKeys: nil
			) else {
				return nil
			}

			sources += enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
		}

		return sources
	}

	@Test
	func declaresEachNotificationNameOnce() throws {
		let sources = try #require(Self.moduleSources(), "the protocol and chat sources are not where the test expects")
		try #require(sources.isEmpty == false)

		let literal = /"(Glasstual\.[A-Za-z0-9.]+)"/
		var occurrences: [String: [String]] = [:]

		for source in sources {
			let contents = try String(contentsOf: source, encoding: .utf8)

			for match in contents.matches(of: literal) {
				occurrences[String(match.output.1), default: []].append(source.lastPathComponent)
			}
		}

		let duplicated = occurrences.filter { $0.value.count > 1 }

		#expect(duplicated.isEmpty, "notification names spelled out more than once: \(duplicated)")
	}
}
