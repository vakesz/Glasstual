// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// User-visible byte counts are formatted here rather than interpolated as
/// raw integers, which keeps the String Catalog entries down to a plain
/// `%@` placeholder that every locale can position freely.
nonisolated enum LocalizedByteCount {
	static func formatted(_ byteCount: UInt64) -> String {
		Int64(clamping: byteCount).formatted(.byteCount(style: .file))
	}
}
