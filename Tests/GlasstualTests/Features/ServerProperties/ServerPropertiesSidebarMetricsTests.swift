// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import SwiftUI
import Testing

/// The pane list is as wide as its longest name, in every language shipped.
@MainActor
@Suite("Server properties sidebar metrics")
struct ServerPropertiesSidebarMetricsTests {
	@Test("The width follows the widest name between its limits")
	func widthFollowsTheWidestName() {
		#expect(ServerPropertiesSidebarMetrics.width(forTitleWidth: 0) == ServerPropertiesSidebarMetrics.minimumWidth)
		#expect(ServerPropertiesSidebarMetrics.width(forTitleWidth: 150.2)
			== 151 + ServerPropertiesSidebarMetrics.rowChrome)
		#expect(ServerPropertiesSidebarMetrics.width(forTitleWidth: 1000) == ServerPropertiesSidebarMetrics.maximumWidth)
	}

	@Test(
		"No pane name is cut in any shipped language, at any sidebar row size",
		arguments: ["en", "hu", "de", "es", "fr", "ja", "pt-BR"]
	)
	func everyPaneNameFits(language: String) {
		let titles = ServerPropertiesSelection.allCases.map { pane in
			var title = pane.title
			title.locale = Locale(identifier: language)
			return String(localized: title)
		}
		for rowSize in [SidebarRowSize.small, .medium, .large] {
			let widest = ServerPropertiesSidebarMetrics.widestTitleWidth(titles, rowSize: rowSize)
			#expect(widest > 0)
			#expect(
				widest + ServerPropertiesSidebarMetrics.rowChrome <= ServerPropertiesSidebarMetrics.maximumWidth,
				"\(language): the widest pane name is \(widest) points"
			)
		}
	}

	@Test("The languages measured are the ones the catalog ships")
	func measuredLanguagesAreTheShippedOnes() {
		let shipped = Set(Bundle.main.localizations.filter { $0 != "Base" })
		#expect(shipped == ["en", "hu", "de", "es", "fr", "ja", "pt-BR"])
	}
}
