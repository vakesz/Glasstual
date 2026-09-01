/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 *    Copyright (c) 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

enum AddressBookStrings {
	static var ignoreUser: String {
		String(localized: .TDCAddressBookSheet.ignoreUser)
	}

	static var trackUser: String {
		String(localized: .TDCAddressBookSheet.trackUser)
	}

	static var ignoreDescription: String {
		String(localized: .TDCAddressBookSheet.ignoreDescription)
	}

	static var trackingDescription: String {
		String(localized: .TDCAddressBookSheet.trackingDescription)
	}

	static var trackingMethodDescription: String {
		String(localized: .TDCAddressBookSheet.trackingMethodDescription)
	}

	static var hostmask: String {
		String(localized: .TDCAddressBookSheet.hostmask)
	}

	static var hostmaskPlaceholder: String {
		String(localized: .TDCAddressBookSheet.enterAHostmaskToIgnore)
	}

	static var nickname: String {
		String(localized: .TDCAddressBookSheet.nickname)
	}

	static var nicknamePlaceholder: String {
		String(localized: .TDCAddressBookSheet.enterAnyNicknameToTrack)
	}

	static var ignoredMessages: String {
		String(localized: .TDCAddressBookSheet.ignoredMessages)
	}

	static var displayAvailabilityMessage: String {
		String(localized: .TDCAddressBookSheet.displayMessageWhenUserBecomesAvailable)
	}

	static var publicMessages: String {
		String(localized: .TDCAddressBookSheet.publicMessages)
	}

	static var privateMessages: String {
		String(localized: .TDCAddressBookSheet.privateMessages)
	}

	static var noticeMessages: String {
		String(localized: .TDCAddressBookSheet.noticeMessages)
	}

	static var clientToClientProtocol: String {
		String(localized: .TDCAddressBookSheet.clientToClientCtcp)
	}

	static var publicHighlights: String {
		String(localized: .TDCAddressBookSheet.publicHighlights)
	}

	static var privateHighlights: String {
		String(localized: .TDCAddressBookSheet.privateHighlights)
	}

	static var generalEventMessages: String {
		String(localized: .TDCAddressBookSheet.generalEventMessages)
	}

	static var fileTransferRequests: String {
		String(localized: .TDCAddressBookSheet.fileTransferRequests)
	}

	static var inlineMedia: String {
		String(localized: .TDCAddressBookSheet.inlineMedia)
	}

	static var hostmaskHelp: String {
		String(localized: .TDCAddressBookSheet.hostmaskFormatAndExamples)
	}

	static var format: String {
		String(localized: .TDCAddressBookSheet.format)
	}

	static var examples: String {
		String(localized: .TDCAddressBookSheet.examples)
	}

	static var hostmaskFormat: String {
		String(localized: .TDCAddressBookSheet.nicknameUsernameAddress)
	}

	static var hostmaskExamples: [String] {
		[
			String(localized: .TDCAddressBookSheet.matchesEveryPossibleUser),
			String(localized: .TDCAddressBookSheet.matchesNicknamesStartingWithFrank),
			String(localized: .TDCAddressBookSheet.matchesUsernameMatt),
			String(localized: .TDCAddressBookSheet.matchesAddressesEndingInInfo),
		]
	}

	static var invalidIgnoreMask: String {
		String(localized: .TDCAddressBookSheet.pleaseEnterAProperlyFormattedIgnore)
	}
}
