/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

extension ComparisonResult {
	/// This ascending result as `order` asks for it. Every `SortComparator` a
	/// table column is built from needs the same flip, and each one used to
	/// carry its own copy of it.
	nonisolated func ordered(by order: SortOrder) -> ComparisonResult { // nonisolated: pure
		guard order == .reverse else { return self }

		return switch self {
		case .orderedAscending: .orderedDescending
		case .orderedDescending: .orderedAscending
		case .orderedSame: .orderedSame
		}
	}
}
