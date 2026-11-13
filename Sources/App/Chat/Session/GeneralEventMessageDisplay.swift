// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

/// How channel membership events appear in the transcript.
nonisolated enum GeneralEventMessageDisplay: String, Codable, Sendable, CaseIterable {
	case show
	case collapse
	case hide
}
