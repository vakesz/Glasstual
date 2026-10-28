// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ServerPropertiesModel {
	var isSaving = false
	var config: ServerConfig
	var selection: ServerPropertiesSelection = .general
	var selectedAddressBookEntryID: String?
	var selectedChannelID: String?
	var selectedHighlightID: String?

	var serverAddress: String
	var serverPort: String
	var proxyAddress: String
	var proxyPort: String
	var proxyUsername: String
	var alternateNicknames: String
	var connectCommands: String

	/** The three keychain-backed fields.

	 Each one starts empty, holds whatever the one keychain read finds, and is
	 only written back to the keychain when the person typed into it. The
	 distinction matters because the read lands after the sheet is on screen:
	 a field seeded from the pending edit alone reads empty until then, and
	 submitting an empty field as an edit is what deletes the stored secret. */
	var serverPassword: String {
		get { serverPasswordText }
		set {
			guard newValue != serverPasswordText else { return }
			serverPasswordText = newValue
			editedSecretFields.insert(.serverPassword)
		}
	}

	var nicknamePassword: String {
		get { nicknamePasswordText }
		set {
			guard newValue != nicknamePasswordText else { return }
			nicknamePasswordText = newValue
			editedSecretFields.insert(.nicknamePassword)
		}
	}

	var proxyPassword: String {
		get { proxyPasswordText }
		set {
			guard newValue != proxyPasswordText else { return }
			proxyPasswordText = newValue
			editedSecretFields.insert(.proxyPassword)
		}
	}

	var serverPasswordText: String
	var nicknamePasswordText: String
	var proxyPasswordText: String

	/// Which of the three fields the person has typed into. A field that is not
	/// in here keeps whatever edit the configuration already carried, so a sheet
	/// dismissed with OK before — or without — the keychain read leaves every
	/// stored secret alone.
	var editedSecretFields: Set<SecretField> = []

	enum SecretField {
		case serverPassword
		case nicknamePassword
		case proxyPassword
	}

	/// What the one keychain read found, by item — the channel keys included.
	/// Empty until it answers.
	var loadedSecrets: [KeychainItem: String] = [:]

	/// The client-side certificate the connection sends, or `nil` when it sends
	/// none. Four rows reading "No Certificate Selected" said the same thing
	/// four times; there is nothing to show when there is no certificate.
	var certificate: ClientCertificateDetails?

	var submission = SubmissionGate()

	/// The bundled network catalog the Server Address field completes against.
	let networkList: NetworkList

	/** The network list a new connection starts on, until a row is chosen.

	 `nil` for a connection that already exists — there is nothing to start it
	 from — and again once a template has been applied, which is what moves the
	 sheet on to the form. */
	var templatePicker: NetworkPickerListModel?

	/** The port and TLS state the field overwrote when it last matched a
	 network, kept so that typing a host no network claims can put them back.

	 A network fills both fields in, which throws away whatever was there; the
	 person who then types their own host is owed what they had, not the last
	 network's defaults. */
	@ObservationIgnored var valuesReplacedByNetwork: PrimaryServerValues?

	/// The address text this last resolved, so re-running the resolution over an
	/// unchanged field neither re-applies a network nor restores anything.
	@ObservationIgnored var lastResolvedAddressText: String

	/// Set while a network is being written into the fields, so the write does
	/// not read as another edit of the address.
	@ObservationIgnored var isApplyingNetwork = false

	/// A port as the field spells it, beside the TLS state that went with it.
	struct PrimaryServerValues {
		let port: String
		let secured: Bool
	}

	/// `offersTemplates` opens the sheet on the network list rather than the
	/// form; it is what the New Server sheet asks for.
	init(config: ServerConfig, networkList: NetworkList = NetworkList(), offersTemplates: Bool = false) {
		self.config = config
		self.networkList = networkList
		templatePicker = offersTemplates ? NetworkPickerListModel(networkList: networkList) : nil
		let fields = DerivedFields(config: config, networkList: networkList)
		lastResolvedAddressText = fields.serverAddress
		serverAddress = fields.serverAddress
		serverPort = fields.serverPort
		proxyAddress = fields.proxyAddress
		proxyPort = fields.proxyPort
		proxyUsername = fields.proxyUsername
		alternateNicknames = fields.alternateNicknames
		connectCommands = fields.connectCommands
		/* Only the unflushed edits, because reading the stored ones means three
		 synchronous keychain lookups. `loadSecrets()` fills the rest in, and
		 until it does an untouched field submits as `.unchanged` rather than as
		 an emptied one. */
		serverPasswordText = config.serverList.first?.pendingServerPassword.value(orStored: nil) ?? ""
		nicknamePasswordText = config.pendingNicknamePassword.value(orStored: nil) ?? ""
		proxyPasswordText = config.pendingProxyPassword.value(orStored: nil) ?? ""
	}

	/** The fields the sheet edits as text, taken apart from the configuration.

	 Rebuilding them used to mean building a whole second `ServerPropertiesModel`
	 and copying seven properties off it, which also started that model's
	 keychain task. */
	struct DerivedFields {
		let serverAddress: String
		let serverPort: String
		let proxyAddress: String
		let proxyPort: String
		let proxyUsername: String
		let alternateNicknames: String
		let connectCommands: String

		init(config: ServerConfig, networkList: NetworkList) {
			let primary = config.serverList.first
			serverAddress = ServerPropertiesModel.displayedServerAddress(
				primary?.serverAddress ?? "",
				in: networkList
			)
			serverPort = String(primary?.serverPort ?? UInt16(ConnectionDefaults.serverPort))
			proxyAddress = config.proxyAddress ?? ""
			proxyPort = String(config.proxyPort)
			proxyUsername = config.proxyUsername ?? ""
			alternateNicknames = config.alternateNicknames.joined(separator: " ")
			connectCommands = config.loginCommands.joined(separator: "\n")
		}
	}

	func apply(_ fields: DerivedFields) {
		serverAddress = fields.serverAddress
		forgetNetworkResolution()
		serverPort = fields.serverPort
		proxyAddress = fields.proxyAddress
		proxyPort = fields.proxyPort
		proxyUsername = fields.proxyUsername
		alternateNicknames = fields.alternateNicknames
		connectCommands = fields.connectCommands
	}

	var displayedChannels: [ConversationConfig] {
		config.conversationList.filter { $0.type == .channel }
	}

	func replace(with config: ServerConfig) {
		self.config = config
		apply(DerivedFields(config: config, networkList: networkList))
		submission.reset()
		/* The secrets come from the one read this sheet already did. Rebuilding
		 them from the config meant three more keychain lookups on the main
		 actor every time anything else on the sheet changed. The replacement is
		 a fresh configuration, so nothing in it has been typed into yet. */
		editedSecretFields = []
		serverPasswordText = secret(
			primaryServer?.pendingServerPassword ?? .unchanged,
			from: primaryServer?.keychainItem
		)
		nicknamePasswordText = secret(config.pendingNicknamePassword, from: config.nicknamePasswordKeychainItem)
		proxyPasswordText = secret(config.pendingProxyPassword, from: config.proxyPasswordKeychainItem)
	}

	/** Reads the sheet's secrets off the main actor.

	 `SecItemCopyMatching` is synchronous and answers at the keychain's pace;
	 one call per secret ran on the main actor for every sheet, for every
	 `replace(with:)`, and for every row of the channel list each time it was
	 drawn. The view runs this once as the sheet opens, and the answers are
	 cached for as long as the sheet lives. */
	func serverListForEditing() -> [ServerEndpoint]? {
		let fault: (ServerPropertiesSelection, String)? =
			if !resolvedPrimaryServerAddress.isValidInternetAddress {
				(.general, CommonValidationStrings.invalidServerAddress)
			} else if !serverPort.isValidInternetPort {
				(.general, CommonValidationStrings.invalidInternetPort)
			} else {
				nil
			}
		if let fault {
			submission.attempt()
			selection = fault.0
			return nil
		}
		return serverList(replacingPrimaryWith: primaryServerForSubmission())
	}

	/** The primary endpoint as the fields on screen describe it.

	 Both submission paths build it here rather than assembling it themselves,
	 which is how they came to disagree about an unreadable port. Validation
	 refuses one before either runs, so the fallback is defence in depth: it
	 keeps the port the endpoint already had, because moving the person to a
	 default port without saying so is the worse answer. */
	func primaryServerForSubmission() -> ServerEndpoint {
		var primary = primaryServer ?? ServerEndpoint()
		primary.serverAddress = resolvedPrimaryServerAddress
		primary.serverPort = UInt16(serverPort) ?? primary.serverPort
		primary.pendingServerPassword = submittedSecret(
			.serverPassword,
			text: serverPassword,
			pending: primary.pendingServerPassword
		)
		return primary
	}

	/// The endpoint list with `server` as its first entry, whether or not there
	/// was one to replace.
	func serverList(replacingPrimaryWith server: ServerEndpoint) -> [ServerEndpoint] {
		var servers = config.serverList
		if servers.isEmpty {
			servers.append(server)
		} else {
			servers[0] = server
		}
		return servers
	}

	func applyServerList(_ servers: [ServerEndpoint]) {
		config.serverList = servers
		let primary = servers.first
		serverAddress = Self.displayedServerAddress(primary?.serverAddress ?? "", in: networkList)
		serverPort = String(primary?.serverPort ?? UInt16(ConnectionDefaults.serverPort))
		forgetNetworkResolution()
		/* The endpoint sheet answers with the edits it collected, so the primary
		 endpoint's secret is whatever came back from it, resolved against the
		 read this sheet already did. Asking `ServerEndpoint.serverPassword` was a
		 synchronous keychain lookup on the main actor for a value that is
		 already here. */
		editedSecretFields.remove(.serverPassword)
		serverPasswordText = secret(primary?.pendingServerPassword ?? .unchanged, from: primary?.keychainItem)
	}

	/// Turns TLS on or off for the primary endpoint, moving the port with it the
	/// way the endpoint-list sheet does.
	func setPrimaryServerSecured(_ secured: Bool) {
		var server = primaryServer ?? ServerEndpoint()
		server.serverPort = UInt16(serverPort) ?? server.serverPort
		server = ServerEndpointValidation.server(server, preferringSecuredConnection: secured)
		serverPort = String(server.serverPort)
		storePrimaryServer(server)
	}

	var primaryServerIsSecured: Bool {
		get { primaryServer?.prefersSecuredConnection ?? false }
		set { setPrimaryServerSecured(newValue) }
	}

	func submittedConfig() -> ServerConfig? {
		guard validate() else { return nil }
		var result = config
		result.serverList = serverList(replacingPrimaryWith: primaryServerForSubmission())
		result.nickname = result.nickname.firstToken
		result.awayNickname = Self.nilIfEmpty(result.awayNickname?.firstToken ?? "")
		result.username = result.username.firstToken
		result.ctcpVersionReply = Self.nilIfEmpty(result.ctcpVersionReply?.trimmed ?? "")
		result.pendingNicknamePassword = submittedSecret(
			.nicknamePassword,
			text: nicknamePassword,
			pending: result.pendingNicknamePassword
		)
		result.alternateNicknames = uniqueNonempty(alternateNicknames.components(separatedBy: .whitespaces))
		result.proxyAddress = Self.nilIfEmpty(proxyAddress.firstToken.lowercased())
		result.proxyPort = UInt16(proxyPort) ?? UInt16(ConnectionDefaults.proxyPort)
		result.proxyUsername = Self.nilIfEmpty(proxyUsername.firstToken)
		result.pendingProxyPassword = submittedSecret(
			.proxyPassword,
			text: proxyPassword,
			pending: result.pendingProxyPassword
		)
		result.loginCommands = connectCommands.components(separatedBy: .newlines)
			.map(\.trimmed).filter { !$0.isEmpty }
		return result
	}

	/** The first field that stops the sheet being saved, and the pane it is on.

	 Recomputed from what is on screen rather than remembered from the last
	 press of Save, so the message goes as soon as the field it named is
	 acceptable and Save comes back with it. */
	var validationFault: (selection: ServerPropertiesSelection, message: String)? {
		if config.connectionName.trimmed
			.isEmpty || !ServerPropertiesValidation.isSingleLine(config.connectionName)
		{
			(.general, CommonValidationStrings.singleLineRequired)
		} else if !resolvedPrimaryServerAddress.isValidInternetAddress {
			(.general, CommonValidationStrings.invalidServerAddress)
		} else if !serverPort.isValidInternetPort {
			(.general, CommonValidationStrings.invalidInternetPort)
		} else if !config.nickname.firstToken.isHostmaskNickname {
			(.identity, CommonValidationStrings.invalidNickname)
		} else if let away = config.awayNickname, !away.isEmpty,
		          !away.firstToken.isHostmaskNickname
		{
			(.identity, CommonValidationStrings.invalidNickname)
		} else if let nickname = ServerPropertiesValidation.invalidAlternateNickname(in: alternateNicknames) {
			(.identity, String(localized: .ServerProperties.pleaseEnterAListOfProperly(nickname)))
		} else if !config.username.firstToken.isHostmaskUsername {
			(.identity, String(localized: .ServerProperties.pleaseEnterAProperlyFormattedUsername))
		} else if !ServerPropertiesValidation.isRealName(config.realName) {
			(.identity, CommonValidationStrings.invalidRealName)
		} else if !ServerPropertiesValidation.isLeavingComment(config.normalLeavingComment) ||
			!ServerPropertiesValidation.isLeavingComment(config.sleepModeLeavingComment)
		{
			(.disconnectMessages, CommonValidationStrings.maximumLength(
				ServerPropertiesValidation.maximumCommentLength
			))
		} else if Self.proxyTypeUsesAddress(config.proxyType),
		          !proxyAddress.firstToken.isValidInternetAddress
		{
			(.proxyServer, String(localized: .ServerProperties.pleaseEnterAProperlyFormattedProxy))
		} else if Self.proxyTypeUsesAddress(config.proxyType), !proxyPort.isValidInternetPort {
			(.proxyServer, CommonValidationStrings.invalidInternetPort)
		} else {
			nil
		}
	}

	/// Why the sheet cannot be saved, once saving has been tried.
	var validationMessage: String? {
		submission.shown(validationFault?.message)
	}

	@discardableResult
	func validate() -> Bool {
		submission.attempt()

		guard let fault = validationFault else { return true }

		selection = fault.selection
		return false
	}

	static func nilIfEmpty(_ value: String) -> String? {
		value.isEmpty ? nil : value
	}

	static func proxyTypeUsesAddress(_ type: ConnectionProxyKind) -> Bool {
		[.socks5, .HTTP].contains(type)
	}

	var primaryServer: ServerEndpoint? {
		config.serverList.first
	}

	func storePrimaryServer(_ server: ServerEndpoint) {
		config.serverList = serverList(replacingPrimaryWith: server)
	}

	func uniqueNonempty(_ values: [String]) -> [String] {
		var seen = Set<String>()
		return values.filter { !$0.isEmpty && seen.insert($0).inserted }
	}
}

extension String {
	var trimmed: String {
		trimmingCharacters(in: .whitespacesAndNewlines)
	}
}
