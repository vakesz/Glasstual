/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 *    Copyright (c) 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

enum AddressBookStrings {
	static var ignoreUser: String {
		String(localized: .AddressBook.ignoreUser)
	}

	static var trackUser: String {
		String(localized: .AddressBook.trackUser)
	}

	static var ignoreDescription: String {
		String(localized: .AddressBook.ignoreDescription)
	}

	static var trackingDescription: String {
		String(localized: .AddressBook.trackingDescription)
	}

	static var trackingMethodDescription: String {
		String(localized: .AddressBook.trackingMethodDescription)
	}

	static var hostmask: String {
		String(localized: .AddressBook.hostmask)
	}

	static var hostmaskPlaceholder: String {
		String(localized: .AddressBook.enterAHostmaskToIgnore)
	}

	static var nickname: String {
		String(localized: .AddressBook.nickname)
	}

	static var nicknamePlaceholder: String {
		String(localized: .AddressBook.enterAnyNicknameToTrack)
	}

	static var ignoredMessages: String {
		String(localized: .AddressBook.ignoredMessages)
	}

	static var displayAvailabilityMessage: String {
		String(localized: .AddressBook.displayMessageWhenUserBecomesAvailable)
	}

	static var publicMessages: String {
		String(localized: .AddressBook.publicMessages)
	}

	static var privateMessages: String {
		String(localized: .AddressBook.privateMessages)
	}

	static var noticeMessages: String {
		String(localized: .AddressBook.noticeMessages)
	}

	static var clientToClientProtocol: String {
		String(localized: .AddressBook.clientToClientCtcp)
	}

	static var publicHighlights: String {
		String(localized: .AddressBook.publicHighlights)
	}

	static var privateHighlights: String {
		String(localized: .AddressBook.privateHighlights)
	}

	static var generalEventMessages: String {
		String(localized: .AddressBook.generalEventMessages)
	}

	static var fileTransferRequests: String {
		String(localized: .AddressBook.fileTransferRequests)
	}

	static var inlineMedia: String {
		String(localized: .AddressBook.inlineMedia)
	}

	static var hostmaskHelp: String {
		String(localized: .AddressBook.hostmaskFormatAndExamples)
	}

	static var format: String {
		String(localized: .AddressBook.format)
	}

	static var examples: String {
		String(localized: .AddressBook.examples)
	}

	static var hostmaskFormat: String {
		String(localized: .AddressBook.nicknameUsernameAddress)
	}

	static var hostmaskExamples: [String] {
		[
			String(localized: .AddressBook.matchesEveryPossibleUser),
			String(localized: .AddressBook.matchesNicknamesStartingWithFrank),
			String(localized: .AddressBook.matchesUsernameMatt),
			String(localized: .AddressBook.matchesAddressesEndingInInfo),
		]
	}

	static var invalidIgnoreMask: String {
		String(localized: .AddressBook.pleaseEnterAProperlyFormattedIgnore)
	}
}
