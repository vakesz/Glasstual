// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

nonisolated extension SettingsKeys {
	/// Where the main window last was and what it was showing. Restored state,
	/// not settings, so the whole family stays out of an exported file.
	enum MainWindow {
		private static let group = "Main Window -> "

		static let sidebarVisible = SettingsKey(
			group + "Sidebar Visible",
			default: true,
			traits: [.unregistered, .excludedFromExport]
		)

		static let memberListVisible = SettingsKey(
			group + "Member List Visible",
			default: true,
			traits: [.unregistered, .excludedFromExport]
		)

		static let sidebarSelection = SettingsKey(
			group + "Sidebar Selection",
			default: "",
			traits: [.unregistered, .excludedFromExport]
		)

		/// Where the user last left the member list's edge, in points.
		static let memberListWidth = SettingsKey(
			group + "Member List Width",
			default: 200.0,
			traits: [.unregistered, .excludedFromExport],
			validation: { MemberListWidthPolicy.clamped(CGFloat($0)) == CGFloat($0) }
		)

		/// The transcript zoom the View menu last left, so Increase and
		/// Decrease Font Size survive a relaunch the way the column widths do.
		static let textSizeMultiplier = SettingsKey(
			group + "Text Size Multiplier",
			default: 1.0,
			traits: [.unregistered, .excludedFromExport],
			validation: { $0.isFinite && $0 >= 0.5 && $0 <= 3.0 }
		)

		static let all: [any AnySettingsKey] = [
			sidebarVisible, memberListVisible, sidebarSelection, memberListWidth,
			textSizeMultiplier,
		]
	}
}
