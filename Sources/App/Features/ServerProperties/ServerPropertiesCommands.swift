// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Everything the connection sheet's content can ask its sheet to do.

 The view draws a configuration and raises editors for the things inside it; the
 sheet owns the child sheets, the certificate panel and the save. This is the
 list of what the first asks of the second, so the sheet hands its content
 itself rather than a literal of seventeen closures. */
@MainActor
protocol ServerPropertiesCommands: AnyObject {
	func submit()
	func cancel()
	/// Continue on the template step a new connection opens on.
	func applyTemplate()
	func editEndpoints()

	func addChannel()
	func editChannel()
	func deleteChannel()

	func addHighlight()
	func editHighlight()
	func deleteHighlight()

	func addIgnoreEntry()
	func addTrackingEntry()
	func editAddressBookEntry()
	func deleteAddressBookEntry()

	func chooseCertificate()
	func resetCertificate()
	/// Puts the NickServ registration command for `fingerprint` on the
	/// pasteboard.
	func copyNickServCommand(for fingerprint: String)
}

/** One of the sheet's three editable lists.

 The three panes are the same list with the same three buttons over different
 contents, so what changes between them -- what each button is called, and which
 command it runs -- is named here once instead of travelling beside every
 closure. */
enum ServerPropertiesListKind {
	case channels
	case highlights
	case addressBook

	var pane: ServerPropertiesSelection {
		switch self {
		case .channels: .channelList
		case .highlights: .highlights
		case .addressBook: .addressBook
		}
	}

	var emptyTitle: LocalizedStringResource {
		switch self {
		case .channels: .ServerProperties.channelsEmptyTitle
		case .highlights: .ServerProperties.highlightsEmptyTitle
		case .addressBook: .ServerProperties.addressBookEmptyTitle
		}
	}

	var emptyDescription: LocalizedStringResource {
		switch self {
		case .channels: .ServerProperties.channelsEmptyDescription
		case .highlights: .ServerProperties.highlightsEmptyDescription
		case .addressBook: .ServerProperties.addressBookEmptyDescription
		}
	}

	var addLabel: LocalizedStringResource {
		switch self {
		case .channels: .ServerProperties.addChannelButton
		case .highlights: .ServerProperties.addHighlightButton
		case .addressBook: .ServerProperties.addAddressBookEntryButton
		}
	}

	var editLabel: LocalizedStringResource {
		switch self {
		case .channels: .ServerProperties.editChannelButton
		case .highlights: .ServerProperties.editHighlightButton
		case .addressBook: .ServerProperties.editAddressBookEntryButton
		}
	}

	var removeLabel: LocalizedStringResource {
		switch self {
		case .channels: .ServerProperties.removeChannelButton
		case .highlights: .ServerProperties.removeHighlightButton
		case .addressBook: .ServerProperties.removeAddressBookEntryButton
		}
	}

	func add(with commands: (any ServerPropertiesCommands)?) {
		switch self {
		case .channels: commands?.addChannel()
		case .highlights: commands?.addHighlight()
		/* The Address Book's plus is a menu, because an entry is either an
		 ignore or a tracked user; asking for one without saying which adds the
		 ignore its button used to. */
		case .addressBook: commands?.addIgnoreEntry()
		}
	}

	func edit(with commands: (any ServerPropertiesCommands)?) {
		switch self {
		case .channels: commands?.editChannel()
		case .highlights: commands?.editHighlight()
		case .addressBook: commands?.editAddressBookEntry()
		}
	}

	func remove(with commands: (any ServerPropertiesCommands)?) {
		switch self {
		case .channels: commands?.deleteChannel()
		case .highlights: commands?.deleteHighlight()
		case .addressBook: commands?.deleteAddressBookEntry()
		}
	}
}
