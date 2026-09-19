// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** One pane of the connection sheet.

 Every case is a pane the sidebar lists and the detail view draws, and it carries
 its own row: the sidebar and the pane's heading used to name the same pane
 twice, once each, so a renamed pane could be called two things at once. The
 entry points a menu can open the sheet at are `ServerPropertiesDestination`,
 which is a different question and used to be mixed in here as two cases nothing
 could select. */
enum ServerPropertiesSelection: CaseIterable, Hashable {
	case general
	case identity
	case channelList
	case highlights
	case addressBook
	case connectCommands
	case disconnectMessages
	case encoding
	case zncBouncer
	case clientCertificate
	case networkSocket
	case proxyServer
	case floodControl

	var title: LocalizedStringResource {
		switch self {
		case .general: .ServerProperties.serverPropertiesNavigationMenuGeneral
		case .identity: .ServerProperties.serverPropertiesNavigationMenuIdentity
		case .channelList: .ServerProperties.channelList
		case .highlights: .ServerProperties.serverPropertiesNavigationMenuHighlights
		case .addressBook: .ServerProperties.addressBook
		case .connectCommands: .ServerProperties.connectCommands
		case .disconnectMessages: .ServerProperties.serverPropertiesNavigationMenuMessages
		case .encoding: .ServerProperties.serverPropertiesNavigationMenuEncoding
		case .zncBouncer: .ServerProperties.zncBouncer
		case .clientCertificate: .ServerProperties.clientCertificate
		case .networkSocket: .ServerProperties.networkSocket
		case .proxyServer: .ServerProperties.proxyServer
		case .floodControl: .ServerProperties.floodControl
		}
	}

	/// The SF Symbol the sidebar row carries.
	var symbol: String {
		switch self {
		case .general: "network"
		case .identity: "person.crop.circle"
		case .channelList: "number"
		case .highlights: "highlighter"
		case .addressBook: "person.2"
		case .connectCommands: "terminal"
		case .disconnectMessages: "text.bubble"
		case .encoding: "character.book.closed"
		case .zncBouncer: "server.rack"
		case .clientCertificate: "checkmark.shield"
		case .networkSocket: "cable.connector"
		case .proxyServer: "arrow.triangle.branch"
		case .floodControl: "speedometer"
		}
	}
}
