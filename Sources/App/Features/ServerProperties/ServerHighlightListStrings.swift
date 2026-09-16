/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

enum ServerHighlightListStrings {
	static func windowTitle(networkName: String) -> String {
		String(localized: .ServerProperties.windowTitle(networkName))
	}

	static var channel: String {
		String(localized: .ServerProperties.channel)
	}

	static var message: String {
		String(localized: .ServerProperties.message)
	}

	static var time: String {
		String(localized: .ServerProperties.time)
	}

	static var highlightList: String {
		String(localized: .ServerProperties.highlightList)
	}

	static var clearList: String {
		String(localized: .ServerProperties.clearList)
	}

	static var clearListConfirmationTitle: String {
		String(localized: .ServerProperties.clearListConfirmationTitle)
	}

	static var clearListConfirmationMessage: String {
		String(localized: .ServerProperties.clearListConfirmationMessage)
	}

	static var goToMessage: String {
		String(localized: .ServerProperties.goToMessage)
	}

	static var actionNote: String {
		String(localized: .ServerProperties.actionNote)
	}

	static var emptyTitle: String {
		String(localized: .ServerProperties.emptyTitle)
	}

	static var emptyDescription: String {
		String(localized: .ServerProperties.emptyDescription)
	}
}
