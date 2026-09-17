// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Observation
import SwiftUI

enum ServerPropertiesValidation {
	static func isSingleLine(_ value: String) -> Bool {
		value.rangeOfCharacter(from: .newlines) == nil
	}

	/** A real name the server will accept on the USER line: something other
	 than whitespace, on one line. Onboarding and the server properties sheet
	 both ask this, so a name one of them accepts the other does not refuse. */
	static func isRealName(_ value: String) -> Bool {
		value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false && isSingleLine(value)
	}

	/// The protocol limits a line in bytes, so a disconnect message is measured
	/// in UTF-8 bytes rather than in characters, which undercount anything
	/// outside ASCII.
	static let maximumCommentLength = 390

	static func isLeavingComment(_ value: String) -> Bool {
		isSingleLine(value) && value.utf8.count <= maximumCommentLength
	}

	/// The first alternative nickname the server would refuse, or `nil` when
	/// every one of them is usable. The message names it, so the check reports
	/// which one rather than only that one of them failed.
	static func invalidAlternateNickname(in value: String) -> String? {
		value.components(separatedBy: .whitespaces)
			.first { $0.isEmpty == false && ($0 as NSString).isHostmaskNickname == false }
	}
}

@MainActor
@Observable
final class ServerPropertiesModel {
	var isSaving = false
	var config: ClientConfig
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

	private var serverPasswordText: String
	private var nicknamePasswordText: String
	private var proxyPasswordText: String

	/// Which of the three fields the person has typed into. A field that is not
	/// in here keeps whatever edit the configuration already carried, so a sheet
	/// dismissed with OK before — or without — the keychain read leaves every
	/// stored secret alone.
	private var editedSecretFields: Set<SecretField> = []

	private enum SecretField {
		case serverPassword
		case nicknamePassword
		case proxyPassword
	}

	/// What the one keychain read found, by item — the channel keys included.
	/// Empty until it answers.
	private var loadedSecrets: [KeychainItem: String] = [:]

	/// The client-side certificate the connection sends, or `nil` when it sends
	/// none. Four rows reading "No Certificate Selected" said the same thing
	/// four times; there is nothing to show when there is no certificate.
	var certificate: ClientCertificateDetails?

	private var submissionWasAttempted = false

	/// The bundled network catalog the Server Address field completes against.
	let networkList: NetworkList

	/** The network list a new connection starts on, until a row is chosen.

	 `nil` for a connection that already exists — there is nothing to start it
	 from — and again once a template has been applied, which is what moves the
	 sheet on to the form. */
	private(set) var templatePicker: NetworkPickerModel?

	/** The port and TLS state the field overwrote when it last matched a
	 network, kept so that typing a host no network claims can put them back.

	 A network fills both fields in, which throws away whatever was there; the
	 person who then types their own host is owed what they had, not the last
	 network's defaults. */
	@ObservationIgnored private var valuesReplacedByNetwork: PrimaryServerValues?

	/// The address text this last resolved, so re-running the resolution over an
	/// unchanged field neither re-applies a network nor restores anything.
	@ObservationIgnored private var lastResolvedAddressText: String

	/// Set while a network is being written into the fields, so the write does
	/// not read as another edit of the address.
	@ObservationIgnored private var isApplyingNetwork = false

	/// A port as the field spells it, beside the TLS state that went with it.
	private struct PrimaryServerValues {
		let port: String
		let secured: Bool
	}

	/// `offersTemplates` opens the sheet on the network list rather than the
	/// form; it is what the New Server sheet asks for.
	init(config: ClientConfig, networkList: NetworkList = NetworkList(), offersTemplates: Bool = false) {
		self.config = config
		self.networkList = networkList
		templatePicker = offersTemplates ? NetworkPickerModel(networkList: networkList) : nil
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
	private struct DerivedFields {
		let serverAddress: String
		let serverPort: String
		let proxyAddress: String
		let proxyPort: String
		let proxyUsername: String
		let alternateNicknames: String
		let connectCommands: String

		init(config: ClientConfig, networkList: NetworkList) {
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

	private func apply(_ fields: DerivedFields) {
		serverAddress = fields.serverAddress
		forgetNetworkResolution()
		serverPort = fields.serverPort
		proxyAddress = fields.proxyAddress
		proxyPort = fields.proxyPort
		proxyUsername = fields.proxyUsername
		alternateNicknames = fields.alternateNicknames
		connectCommands = fields.connectCommands
	}

	var displayedChannels: [ChannelConfig] {
		config.channelList.filter { $0.type == .channel }
	}

	func replace(with config: ClientConfig) {
		self.config = config
		apply(DerivedFields(config: config, networkList: networkList))
		submissionWasAttempted = false
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
	func loadSecrets() async {
		let passwords = await KeychainSecretLoader.passwords(for: secretKeychainItems)
		applyLoadedSecrets(passwords)
	}

	/** Describes the client certificate the connection sends, off the main
	 actor, and clears the description when it sends none.

	 The certificate is a persistent keychain reference, so naming it and
	 digesting it is a `SecItemCopyMatching` like the passwords: read as the
	 sheet opens, it was the stall between the click and the sheet. The view
	 runs this again whenever the reference changes, which cancels a read of
	 the previous one. */
	func loadCertificate() async {
		guard let reference = config.identityClientSideCertificate else {
			certificate = nil
			return
		}
		let details = await ClientCertificateLoader.certificate(for: reference)
		guard Task.isCancelled == false, reference == config.identityClientSideCertificate else { return }
		certificate = details
	}

	/// Whether the channel list shows a channel as having a key: an unflushed
	/// edit if there is one, and otherwise what the one keychain read found.
	func channelHasSecretKey(_ channel: ChannelConfig) -> Bool {
		channel.pendingSecretKey.value(orStored: loadedSecrets[channel.keychainItem])?.isEmpty == false
	}

	private var secretKeychainItems: [KeychainItem] {
		var items = [config.nicknamePasswordKeychainItem, config.proxyPasswordKeychainItem]

		if let primaryServer {
			items.append(primaryServer.keychainItem)
		}

		return items + displayedChannels.map(\.keychainItem)
	}

	private func applyLoadedSecrets(_ passwords: [KeychainItem: String]) {
		guard Task.isCancelled == false else { return }
		loadedSecrets = passwords

		/* A field the user has already typed into keeps what they typed — an
		 emptied one included, which is why this asks what was edited rather
		 than what is empty. */
		if editedSecretFields.contains(.serverPassword) == false {
			serverPasswordText = secret(
				primaryServer?.pendingServerPassword ?? .unchanged,
				from: primaryServer?.keychainItem
			)
		}
		if editedSecretFields.contains(.nicknamePassword) == false {
			nicknamePasswordText = secret(config.pendingNicknamePassword, from: config.nicknamePasswordKeychainItem)
		}
		if editedSecretFields.contains(.proxyPassword) == false {
			proxyPasswordText = secret(config.pendingProxyPassword, from: config.proxyPasswordKeychainItem)
		}
	}

	/// An unflushed edit if there is one, and otherwise what the one keychain
	/// read found. Never a keychain read of its own.
	private func secret(_ pending: PendingKeychainSecret, from item: KeychainItem?) -> String {
		pending.value(orStored: item.flatMap { loadedSecrets[$0] }) ?? ""
	}

	/** What submitting one of the three fields asks the keychain to do.

	 Only a field the person typed into carries an instruction; every other one
	 hands back the edit the configuration already had, which is normally
	 `.unchanged`. Emitting `.edited(text)` for an untouched field wrote
	 `.cleared` for as long as the keychain read had not landed, which deleted
	 the secret the sheet had not finished showing. */
	private func submittedSecret(
		_ field: SecretField,
		text: String,
		pending: PendingKeychainSecret
	) -> PendingKeychainSecret {
		editedSecretFields.contains(field) ? .edited(text.trimmed) : pending
	}

	func serverListForEditing() -> [Server]? {
		let fault: (ServerPropertiesSelection, String)? =
			if !(resolvedPrimaryServerAddress as NSString).isValidInternetAddress {
				(.general, CommonValidationStrings.invalidServerAddress)
			} else if !(serverPort as NSString).isValidInternetPort {
				(.general, CommonValidationStrings.invalidInternetPort)
			} else {
				nil
			}
		if let fault {
			submissionWasAttempted = true
			selection = fault.0
			return nil
		}
		var servers = config.serverList
		var primary = primaryServer ?? Server()
		primary.serverAddress = resolvedPrimaryServerAddress
		primary.serverPort = UInt16(serverPort) ?? primary.serverPort
		primary.pendingServerPassword = submittedSecret(
			.serverPassword,
			text: serverPassword,
			pending: primary.pendingServerPassword
		)
		if servers.isEmpty {
			servers.append(primary)
		} else {
			servers[0] = primary
		}
		return servers
	}

	func applyServerList(_ servers: [Server]) {
		config.serverList = servers
		let primary = servers.first
		serverAddress = Self.displayedServerAddress(primary?.serverAddress ?? "", in: networkList)
		serverPort = String(primary?.serverPort ?? UInt16(ConnectionDefaults.serverPort))
		forgetNetworkResolution()
		/* The endpoint sheet answers with the edits it collected, so the primary
		 endpoint's secret is whatever came back from it, resolved against the
		 read this sheet already did. Asking `Server.serverPassword` was a
		 synchronous keychain lookup on the main actor for a value that is
		 already here. */
		editedSecretFields.remove(.serverPassword)
		serverPasswordText = secret(primary?.pendingServerPassword ?? .unchanged, from: primary?.keychainItem)
	}

	/// Turns TLS on or off for the primary endpoint, moving the port with it the
	/// way the endpoint-list sheet does.
	func setPrimaryServerSecured(_ secured: Bool) {
		var server = primaryServer ?? Server()
		server.serverPort = UInt16(serverPort) ?? server.serverPort
		server = ServerEndpointValidation.server(server, preferringSecuredConnection: secured)
		serverPort = String(server.serverPort)
		storePrimaryServer(server)
	}

	var primaryServerIsSecured: Bool {
		get { primaryServer?.prefersSecuredConnection ?? false }
		set { setPrimaryServerSecured(newValue) }
	}

	// MARK: - Templates

	var isChoosingTemplate: Bool {
		templatePicker != nil
	}

	/// Continue is offered once a row is chosen; the custom server row counts.
	var canApplyTemplate: Bool {
		templatePicker?.hasSelection ?? false
	}

	/** Fills the connection in from the chosen row and moves on to the form.

	 The custom server row moves on with the fields as they are. A network sets
	 the connection's name and primary endpoint, turns SASL on where the network
	 offers it, and puts its suggested channels on the channel list, where the
	 Channel List pane can take any of them off again. */
	func applySelectedTemplate() {
		guard let picker = templatePicker, picker.hasSelection else { return }

		if let network = picker.selectedNetwork {
			var config = config
			config.connectionName = network.networkName
			config.serverList = [
				Server(
					serverAddress: network.serverAddress,
					serverPort: network.serverPort,
					prefersSecuredConnection: network.prefersSecuredConnection
				),
			]
			config.usesSASL = network.saslSupported
			config.channelList = network.suggestedChannels.map { ChannelConfig.seed(withName: $0) }
			replace(with: config)
		}

		templatePicker = nil
		selection = .general
	}

	// MARK: - Bundled networks

	/** What the Server Address field offers to complete to.

	 An empty field leads with the popular networks and then lists the rest, the
	 way the onboarding picker does; typing narrows the whole catalog by name and
	 by address. The onboarding picker's matcher also reads the network's blurb,
	 which belongs to a browsing list rather than to an address field, so this
	 keeps its own. */
	var serverAddressSuggestions: [Network] {
		let query = serverAddress.trimmed

		guard query.isEmpty == false else {
			return networkList.popularNetworks + networkList.networksBelowThePopularOnes
		}

		return networkList.listOfNetworks.filter {
			$0.networkName.localizedCaseInsensitiveContains(query)
				|| $0.serverAddress.localizedCaseInsensitiveContains(query)
		}
	}

	/** The address to connect to, which is not always the address on screen.

	 The field shows a network by name — "Libera.Chat" rather than
	 `irc.libera.chat` — so what is stored is the catalog's address for the
	 network the text names, and otherwise the host as typed. Three network names
	 hold a space, which is also why the name is resolved before the text is cut
	 down to its first token. */
	var resolvedPrimaryServerAddress: String {
		if let network = networkList.network(named: serverAddress.trimmed) {
			return network.serverAddress
		}

		return serverAddress.firstToken.lowercased()
	}

	/** Fills the port and TLS fields in from the network the address now names.

	 Called for each edit of the field. A value that names a network — by its
	 name or by its address — is replaced with the network's name and brings the
	 network's port and TLS state with it; a value that names none puts back
	 whatever the last network overwrote, once. */
	func serverAddressTextDidChange() {
		guard isApplyingNetwork == false else { return }

		let text = serverAddress.trimmed

		guard text != lastResolvedAddressText else { return }

		lastResolvedAddressText = text

		guard let network = networkList.network(named: text) ?? networkList.network(withServerAddress: text)
		else {
			restorePreviousValuesForPrimaryServer()
			return
		}

		isApplyingNetwork = true
		defer { isApplyingNetwork = false }

		if valuesReplacedByNetwork == nil {
			valuesReplacedByNetwork = PrimaryServerValues(port: serverPort, secured: primaryServerIsSecured)
		}

		serverAddress = network.networkName
		lastResolvedAddressText = network.networkName
		applyPrimaryServerValues(
			PrimaryServerValues(port: String(network.serverPort), secured: network.prefersSecuredConnection)
		)
	}

	/// The network name a stored address is listed under, or the address itself
	/// when the catalog does not list it.
	private static func displayedServerAddress(_ serverAddress: String, in networkList: NetworkList) -> String {
		networkList.network(withServerAddress: serverAddress)?.networkName ?? serverAddress
	}

	private func restorePreviousValuesForPrimaryServer() {
		guard let previous = valuesReplacedByNetwork else { return }

		valuesReplacedByNetwork = nil
		applyPrimaryServerValues(previous)
	}

	/** Writes a port and a TLS state together.

	 `setPrimaryServerSecured(_:)` moves the port between 6667 and 6697 as the
	 endpoint sheet does, which is right for a toggle the person flipped and
	 wrong here: both values are being replaced at once, so neither may nudge
	 the other. */
	private func applyPrimaryServerValues(_ values: PrimaryServerValues) {
		var server = primaryServer ?? Server()
		server.serverPort = UInt16(values.port) ?? server.serverPort
		server.prefersSecuredConnection = values.secured
		storePrimaryServer(server)
		serverPort = values.port
	}

	/// Forgets what the field last resolved, for a sheet whose fields have just
	/// been replaced wholesale: nothing a network overwrote is still on screen.
	private func forgetNetworkResolution() {
		valuesReplacedByNetwork = nil
		lastResolvedAddressText = serverAddress.trimmed
	}

	func submittedConfig() -> ClientConfig? {
		guard validate() else { return nil }
		var result = config
		var server = primaryServer ?? Server()
		server.serverAddress = resolvedPrimaryServerAddress
		server.serverPort = UInt16(serverPort) ?? UInt16(ConnectionDefaults.serverPort)
		server.pendingServerPassword = submittedSecret(
			.serverPassword,
			text: serverPassword,
			pending: server.pendingServerPassword
		)
		if result.serverList.isEmpty {
			result.serverList = [server]
		} else {
			result.serverList[0] = server
		}
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
		} else if !(resolvedPrimaryServerAddress as NSString).isValidInternetAddress {
			(.general, CommonValidationStrings.invalidServerAddress)
		} else if !(serverPort as NSString).isValidInternetPort {
			(.general, CommonValidationStrings.invalidInternetPort)
		} else if !(config.nickname.firstToken as NSString).isHostmaskNickname {
			(.identity, CommonValidationStrings.invalidNickname)
		} else if let away = config.awayNickname, !away.isEmpty,
		          !(away.firstToken as NSString).isHostmaskNickname
		{
			(.identity, CommonValidationStrings.invalidNickname)
		} else if let nickname = ServerPropertiesValidation.invalidAlternateNickname(in: alternateNicknames) {
			(.identity, String(localized: .ServerProperties.pleaseEnterAListOfProperly(nickname)))
		} else if !(config.username.firstToken as NSString).isHostmaskUsername {
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
		          !(proxyAddress.firstToken as NSString).isValidInternetAddress
		{
			(.proxyServer, String(localized: .ServerProperties.pleaseEnterAProperlyFormattedProxy))
		} else if Self.proxyTypeUsesAddress(config.proxyType), !(proxyPort as NSString).isValidInternetPort {
			(.proxyServer, CommonValidationStrings.invalidInternetPort)
		} else {
			nil
		}
	}

	/** Why the sheet cannot be saved, once saving has been tried.

	 A new connection opens on empty fields, and a sheet that greets the person
	 with a complaint about a field they have not reached yet is telling them
	 they did something wrong before they did anything. */
	var validationMessage: String? {
		submissionWasAttempted ? validationFault?.message : nil
	}

	@discardableResult
	func validate() -> Bool {
		submissionWasAttempted = true

		guard let fault = validationFault else { return true }

		selection = fault.selection
		return false
	}

	static func nilIfEmpty(_ value: String) -> String? {
		value.isEmpty ? nil : value
	}

	static func proxyTypeUsesAddress(_ type: ConnectionProxyType) -> Bool {
		[.socks5, .HTTP].contains(type)
	}

	private var primaryServer: Server? {
		config.serverList.first
	}

	private func storePrimaryServer(_ server: Server) {
		if config.serverList.isEmpty {
			config.serverList.append(server)
		} else {
			config.serverList[0] = server
		}
	}

	private func uniqueNonempty(_ values: [String]) -> [String] {
		var seen = Set<String>()
		return values.filter { !$0.isEmpty && seen.insert($0).inserted }
	}
}

private extension String {
	var trimmed: String {
		trimmingCharacters(in: .whitespacesAndNewlines)
	}
}

/// The copy the connection sheet names these choices with. Each one is a
/// closed set the sheet draws a picker or a row from, so the name belongs to
/// the case rather than to the view that happens to show it.
extension AddressBookEntryType {
	var listTitle: LocalizedStringResource {
		switch self {
		case .ignore, .mixed: .ServerProperties.userIgnore
		case .userTracking: .ServerProperties.userTracking
		@unknown default: .ServerProperties.userIgnore
		}
	}
}

extension ConnectionAddressType {
	var title: LocalizedStringResource {
		switch self {
		case .default: .ServerProperties.addressTypeAutomatic
		case .v4: .ServerProperties.addressTypeIpv4
		case .v6: .ServerProperties.addressTypeIpv6
		}
	}
}

extension ConnectionProxyType {
	var title: LocalizedStringResource {
		switch self {
		case .none: .ServerProperties.proxyTypeNone
		case .automatic: .ServerProperties.proxyTypeAutomatic
		case .socks5: .ServerProperties.proxyTypeSocks5
		case .HTTP: .ServerProperties.proxyTypeHttp
		case .tor: .ServerProperties.proxyTypeTor
		}
	}
}

extension CipherSuiteCollection {
	var title: LocalizedStringResource {
		switch self {
		case .default: .ServerProperties.cipherSuitesDefault
		case .mozilla2017: .ServerProperties.cipherSuitesMozilla2017
		case .mozilla2015: .ServerProperties.cipherSuitesMozilla2015
		case .none: .ServerProperties.cipherSuitesNone
		}
	}
}
