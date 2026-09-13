/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual

/// The one page shape history tests read back with: everything a view holds,
/// oldest first. The store answers fetches with an outcome, and a test that is
/// checking what was written wants the rows.
extension HistoricLogFetchRequest {
	static func newestEntries(forView identifier: String, fetchLimit: UInt) -> Self {
		Self(
			viewIdentifier: identifier,
			kind: .newest(ascending: true, fetchLimit: fetchLimit, limitToDate: nil)
		)
	}
}

/// The rows a page carried. A failure and an empty page answer alike, so this
/// belongs to the tests that have already established which of the two they
/// are looking at; everything the application does reads the case.
extension HistoricLogFetchOutcome {
	nonisolated var entries: [HistoricLogEntry] { // nonisolated: pure
		if case let .page(entries) = self {
			entries
		} else {
			[]
		}
	}
}
