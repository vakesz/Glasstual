// Copyright (c) 2018 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Combine
import Observation
import os

/// Which of the two appearances the application draws in.
enum AppearanceMode: UInt, Sendable {
	case light
	case dark
}
