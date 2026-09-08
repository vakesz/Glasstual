/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/// A database name the store cannot change.
///
/// `HistoricLogStore` names the file itself only when it finds the slot empty,
/// so filling it in up front lets a test seed the database before the store
/// opens it and read it back afterwards, and lets the store's isolation domain
/// answer from a `let` instead of a box it would have to share with the test.
/// Every history test wants a rename reported rather than followed, so the
/// setter records an issue instead of storing.
nonisolated struct HistoricLogFilenameFixture: HistoricLogFilenameStoring { // nonisolated: value
	let filename: String

	init(_ filename: String = "history.sqlite") {
		self.filename = filename
	}

	/// A name no other store in the process shares, for suites that keep
	/// several databases side by side in one temporary directory.
	static func unique(_ prefix: String = "historic-log") -> Self {
		Self("\(prefix)_\(UUID().uuidString).sqlite")
	}

	var databaseFilename: String? {
		get { filename }
		nonmutating set {
			Issue.record("The store renamed its database from \(filename) to \(newValue ?? "nothing").")
		}
	}
}
