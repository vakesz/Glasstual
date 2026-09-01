/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

enum ServerHighlightListStrings {
	static func windowTitle(networkName: String) -> String {
		String(localized: .TDCServerHighlightListSheet.windowTitle(networkName))
	}

	static func heading(networkName: String) -> String {
		String(localized: .TDCServerHighlightListSheet.heading(networkName))
	}

	static var channel: String {
		String(localized: .TDCServerHighlightListSheet.channel)
	}

	static var message: String {
		String(localized: .TDCServerHighlightListSheet.message)
	}

	static var time: String {
		String(localized: .TDCServerHighlightListSheet.time)
	}

	static var highlightList: String {
		String(localized: .TDCServerHighlightListSheet.highlightList)
	}

	static var clearList: String {
		String(localized: .TDCServerHighlightListSheet.clearList)
	}

	static var actionNote: String {
		String(localized: .TDCServerHighlightListSheet.actionNote)
	}

	static var emptyTitle: String {
		String(localized: .TDCServerHighlightListSheet.emptyTitle)
	}

	static var emptyDescription: String {
		String(localized: .TDCServerHighlightListSheet.emptyDescription)
	}
}
