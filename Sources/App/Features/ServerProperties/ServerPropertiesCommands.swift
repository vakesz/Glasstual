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

	func chooseCertificate()
	func resetCertificate()
	/// Puts the NickServ registration command for `fingerprint` on the
	/// pasteboard.
	func copyNickServCommand(for fingerprint: String)
}

/** One of the sheet's two editable lists.

 The two panes are the same list with the same three buttons over different
 contents, so what changes between them -- what each button is called, and which
 command it runs -- is named here once instead of travelling beside every
 closure. */
enum ServerPropertiesListKind {
	case channels
	case highlights

	var pane: ServerPropertiesSelection {
		switch self {
		case .channels: .channelList
		case .highlights: .highlights
		}
	}

	var emptyTitle: LocalizedStringResource {
		switch self {
		case .channels: .ServerProperties.channelsEmptyTitle
		case .highlights: .ServerProperties.highlightsEmptyTitle
		}
	}

	var emptyDescription: LocalizedStringResource {
		switch self {
		case .channels: .ServerProperties.channelsEmptyDescription
		case .highlights: .ServerProperties.highlightsEmptyDescription
		}
	}

	var addLabel: LocalizedStringResource {
		switch self {
		case .channels: .ServerProperties.addChannelButton
		case .highlights: .ServerProperties.addHighlightButton
		}
	}

	var editLabel: LocalizedStringResource {
		switch self {
		case .channels: .ServerProperties.editChannelButton
		case .highlights: .ServerProperties.editHighlightButton
		}
	}

	var removeLabel: LocalizedStringResource {
		switch self {
		case .channels: .ServerProperties.removeChannelButton
		case .highlights: .ServerProperties.removeHighlightButton
		}
	}

	func add(with commands: (any ServerPropertiesCommands)?) {
		switch self {
		case .channels: commands?.addChannel()
		case .highlights: commands?.addHighlight()
		}
	}

	func edit(with commands: (any ServerPropertiesCommands)?) {
		switch self {
		case .channels: commands?.editChannel()
		case .highlights: commands?.editHighlight()
		}
	}

	func remove(with commands: (any ServerPropertiesCommands)?) {
		switch self {
		case .channels: commands?.deleteChannel()
		case .highlights: commands?.deleteHighlight()
		}
	}
}
