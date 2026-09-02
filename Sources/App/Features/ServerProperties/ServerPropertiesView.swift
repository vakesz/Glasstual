/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import SwiftUI

struct ServerPropertiesActions {
	let submit: () -> Void
	let cancel: () -> Void
	let editEndpoints: () -> Void
	let addChannel: () -> Void
	let editChannel: () -> Void
	let deleteChannel: () -> Void
	let addHighlight: () -> Void
	let editHighlight: () -> Void
	let deleteHighlight: () -> Void
	let addIgnore: () -> Void
	let addTracking: () -> Void
	let editAddressBookEntry: () -> Void
	let deleteAddressBookEntry: () -> Void
	let chooseCertificate: () -> Void
	let resetCertificate: () -> Void
	let copyCertificateFingerprint: (String) -> Void
	let showCipherSuites: () -> Void
}

struct ServerPropertiesView: View {
	@Bindable var model: ServerPropertiesModel
	@Environment(\.openURL) private var openURL
	let actions: ServerPropertiesActions

	private static let networkProxySettingsURL = URL(
		string: "x-apple.systempreferences:com.apple.Network-Settings.extension?Proxies"
	)

	private let encodings: [(value: UInt, title: String)] = {
		let values = String.Encoding.supportedEncodingsByTitle(favoringUTF8: false)
		return values.map { ($0.value.uintValue, $0.key) }.sorted { $0.title < $1.title }
	}()

	var body: some View {
		VStack(spacing: 0) {
			NavigationSplitView {
				List(selection: $model.selection) {
					Section(ServerPropertiesStrings.Navigation.serverProperties) {
						navigationRow(.general, ServerPropertiesStrings.Navigation.general, "network")
						navigationRow(.identity, ServerPropertiesStrings.Navigation.identity, "person.crop.circle")
						navigationRow(.autojoin, ServerPropertiesStrings.Navigation.channelList, "number")
						navigationRow(.highlights, ServerPropertiesStrings.Navigation.highlights, "highlighter")
						navigationRow(.addressBook, ServerPropertiesStrings.Navigation.addressBook, "person.2")
						navigationRow(.connectCommands, ServerPropertiesStrings.Navigation.connectCommands, "terminal")
						navigationRow(.disconnectMessages, ServerPropertiesStrings.Navigation.messages, "text.bubble")
						navigationRow(.encoding, ServerPropertiesStrings.Navigation.encoding, "character.book.closed")
					}
					Section(ServerPropertiesStrings.Navigation.vendorSpecific) {
						navigationRow(.zncBouncer, ServerPropertiesStrings.Navigation.zncBouncer, "server.rack")
					}
					Section(ServerPropertiesStrings.Navigation.advanced) {
						navigationRow(
							.clientCertificate,
							ServerPropertiesStrings.Navigation.clientCertificate,
							"checkmark.shield"
						)
						navigationRow(
							.networkSocket,
							ServerPropertiesStrings.Navigation.networkSocket,
							"cable.connector"
						)
						navigationRow(
							.proxyServer,
							ServerPropertiesStrings.Navigation.proxyServer,
							"arrow.triangle.branch"
						)
						navigationRow(.floodControl, ServerPropertiesStrings.Navigation.floodControl, "speedometer")
						navigationRow(
							.redundancy,
							ServerPropertiesStrings.Navigation.redundancy,
							"arrow.triangle.2.circlepath"
						)
					}
				}
				.listStyle(.sidebar)
				.navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
			} detail: {
				ScrollView {
					selectedPane
						.frame(maxWidth: 680, alignment: .topLeading)
						.padding(24)
				}
				.popover(isPresented: $model.isValidationMessagePresented) {
					if let message = model.validationMessage {
						Text(verbatim: message).padding(12)
					}
				}
			}
			/* A sheet has no toolbar to put a sidebar toggle in, so the one the
			 split view adds by default lands on top of the section list. The
			 list is always visible here anyway. */
			.toolbar(removing: .sidebarToggle)

			Divider()
			HStack {
				Spacer()
				Button(PromptStrings.Action.cancel, action: actions.cancel)
					.keyboardShortcut(.cancelAction)
				Button("Save", action: actions.submit)
					.keyboardShortcut(.defaultAction)
			}
			.padding(12)
		}
		.frame(minWidth: 820, minHeight: 590)
		.onExitCommand(perform: actions.cancel)
	}

	@ViewBuilder
	private var selectedPane: some View {
		switch model.selection {
		case .default, .general: generalPane
		case .identity: identityPane
		case .autojoin: channelPane
		case .highlights: highlightPane
		case .addressBook, .newIgnoreEntry: addressBookPane
		case .connectCommands: commandsPane
		case .disconnectMessages: messagesPane
		case .encoding: encodingPane
		case .zncBouncer: zncPane
		case .clientCertificate: certificatePane
		case .networkSocket: socketPane
		case .proxyServer: proxyPane
		case .floodControl: floodPane
		case .redundancy: redundancyPane
		}
	}

	private func navigationRow(_ selection: ServerPropertiesSelection, _ title: String, _ symbol: String) -> some View {
		Label(title, systemImage: symbol).tag(selection)
	}

	private var generalPane: some View {
		pane(ServerPropertiesStrings.Navigation.general) {
			Form {
				TextField("Connection Name", text: $model.config.connectionName)
				TextField("Server Address", text: $model.serverAddress)
				TextField("Port", text: $model.serverPort)
				SecureField("Server Password", text: $model.serverPassword)
				Toggle("Connect Securely", isOn: $model.primaryServerIsSecured)
				Button("Modify Alternate Servers", action: actions.editEndpoints)
				Divider()
				Toggle("Connect when Glasstual opens", isOn: $model.config.autoConnect)
				Toggle("Reconnect after disconnect", isOn: $model.config.autoReconnect)
				Toggle("Disconnect when the computer sleeps", isOn: $model.config.autoSleepModeDisconnect)
			}
		}
	}

	private var identityPane: some View {
		pane(ServerPropertiesStrings.Navigation.identity) {
			Form {
				TextField("Nickname", text: $model.config.nickname)
				TextField("Away Nickname", text: optionalBinding(\.awayNickname))
				TextField("Alternative Nicknames", text: $model.alternateNicknames)
				TextField("Username", text: $model.config.username)
				TextField("Real Name", text: $model.config.realName)
				TextField("CTCP VERSION Reply", text: optionalBinding(\.ctcpVersionReply))
				SecureField("NickServ or SASL Password", text: $model.nicknamePassword)
				Divider()
				Toggle("Wait for identification before joining channels", isOn: $model.config.autojoinWaitsForNickServ)
				Toggle("Warn if channels cannot be joined", isOn: warningBinding)
				Toggle("Disconnect if SASL authentication fails", isOn: $model.config.disconnectOnSASLFailure)
			}
		}
	}

	private var channelPane: some View {
		pane(ServerPropertiesStrings.Navigation.channelList) {
			List(selection: $model.selectedChannelID) {
				ForEach(model.displayedChannels, id: \.uniqueIdentifier) { channel in
					HStack {
						Toggle("", isOn: channelAutoJoinBinding(channel.uniqueIdentifier)).labelsHidden()
						Text(verbatim: channel.channelName)
						Spacer()
						if let key = channel.secretKey, !key.isEmpty {
							Image(systemName: "key.fill")
						}
					}.tag(channel.uniqueIdentifier)
				}
			}
			.frame(minHeight: 300)
			listButtons(add: actions.addChannel, edit: actions.editChannel, delete: actions.deleteChannel,
			            selectionExists: model.selectedChannelID != nil)
		}
	}

	private var highlightPane: some View {
		pane(ServerPropertiesStrings.Navigation.highlights) {
			List(selection: $model.selectedHighlightID) {
				ForEach(model.config.highlightList, id: \.uniqueIdentifier) { entry in
					VStack(alignment: .leading) {
						Text(verbatim: entry.matchKeyword)
						Text(verbatim: ServerPropertiesStrings.Highlight.matchType(isExcluded: entry.matchIsExcluded))
							.font(.caption).foregroundStyle(.secondary)
					}.tag(entry.uniqueIdentifier)
				}
			}.frame(minHeight: 300)
			listButtons(add: actions.addHighlight, edit: actions.editHighlight, delete: actions.deleteHighlight,
			            selectionExists: model.selectedHighlightID != nil)
		}
	}

	private var addressBookPane: some View {
		pane(ServerPropertiesStrings.Navigation.addressBook) {
			List(selection: $model.selectedAddressBookEntryID) {
				ForEach(model.config.ignoreList, id: \.uniqueIdentifier) { entry in
					VStack(alignment: .leading) {
						Text(verbatim: entry.hostmask)
						Text(verbatim: ServerPropertiesStrings.AddressBook.entryType(entry.entryType))
							.font(.caption).foregroundStyle(.secondary)
					}.tag(entry.uniqueIdentifier)
				}
			}.frame(minHeight: 300)
			HStack {
				Menu {
					Button("Add User Ignore Entry", action: actions.addIgnore)
					Button("Add User Tracking Entry", action: actions.addTracking)
				} label: { Image(systemName: "plus") }
				Button(action: actions.editAddressBookEntry) { Image(systemName: "pencil") }
					.disabled(model.selectedAddressBookEntryID == nil)
				Button(role: .destructive, action: actions.deleteAddressBookEntry) { Image(systemName: "minus") }
					.disabled(model.selectedAddressBookEntryID == nil)
				Spacer()
			}
			.buttonStyle(.borderless)
		}
	}

	private var commandsPane: some View {
		pane(ServerPropertiesStrings.Navigation.connectCommands) {
			Text("Perform commands on connect:").frame(maxWidth: .infinity, alignment: .leading)
			TextEditor(text: $model.connectCommands).font(.system(.body, design: .monospaced)).frame(minHeight: 280)
			Toggle("Set invisible (+i) mode on connect", isOn: $model.config.setInvisibleModeOnConnect)
			Toggle("Run commands silently", isOn: $model.config.runConnectCommandsSilently)
		}
	}

	private var messagesPane: some View {
		pane(ServerPropertiesStrings.Navigation.messages) {
			Form {
				TextField("Part and Quit Message", text: $model.config.normalLeavingComment)
				TextField("Computer Sleep Quit Message", text: $model.config.sleepModeLeavingComment)
			}
		}
	}

	private var encodingPane: some View {
		pane(ServerPropertiesStrings.Navigation.encoding) {
			Form {
				Picker("Encoding", selection: $model.config.primaryEncoding) {
					ForEach(encodings, id: \.value) { Text(verbatim: $0.title).tag($0.value) }
				}
				Picker("Fallback", selection: $model.config.fallbackEncoding) {
					ForEach(encodings, id: \.value) { Text(verbatim: $0.title).tag($0.value) }
				}
			}
		}
	}

	private var zncPane: some View {
		pane(ServerPropertiesStrings.Navigation.zncBouncer) {
			Toggle("Do not automatically join channels on connect", isOn: $model.config.zncIgnoreConfiguredAutojoin)
			Toggle(
				"Do not show notifications for the playback buffer",
				isOn: $model.config.zncIgnorePlaybackNotifications
			)
			Toggle("Only play back messages you missed", isOn: $model.config.zncOnlyPlaybackLatest)
			Text("These options target ZNC 1.2 and later.").foregroundStyle(.secondary)
		}
	}

	private var certificatePane: some View {
		pane(ServerPropertiesStrings.Navigation.clientCertificate) {
			Form {
				LabeledContent("Certificate Name", value: model.certificateName)
				fingerprint("SHA-512 Fingerprint", model.certificateSHA512)
				fingerprint("SHA-256 Fingerprint", model.certificateSHA256)
				fingerprint("SHA-1 Fingerprint", model.certificateSHA1)
			}
			HStack {
				Button("Select Certificate", action: actions.chooseCertificate)
				Button("Reset Certificate", action: actions.resetCertificate)
					.disabled(model.config.identityClientSideCertificate == nil)
			}
		}
	}

	private var socketPane: some View {
		pane(ServerPropertiesStrings.Navigation.networkSocket) {
			Picker("Connect using", selection: $model.config.addressType) {
				Text("Automatically choose").tag(IRCConnectionAddressType.default)
				Text("IPv4").tag(IRCConnectionAddressType.v4)
				Text("IPv6").tag(IRCConnectionAddressType.v6)
			}.pickerStyle(.radioGroup)
			Toggle("Validate the certificate chain when connecting", isOn: $model.config.validateServerCertificateChain)
			Toggle("Periodically PING the server", isOn: $model.config.performPongTimer)
			Toggle("Disconnect when no PING response is received", isOn: $model.config.performDisconnectOnPongTimer)
			Toggle("Disconnect when reachability changes", isOn: $model.config.performDisconnectOnReachabilityChange)
			Picker("Cipher suites", selection: $model.config.cipherSuites) {
				Text("Default list").tag(CipherSuiteCollection.default)
				Text("Version 7.0.0 list").tag(CipherSuiteCollection.mozilla2017)
				Text("Version 5.2.7 list").tag(CipherSuiteCollection.mozilla2015)
				Text("Do not prefer specific suites").tag(CipherSuiteCollection.none)
			}
			Button("View List", action: actions.showCipherSuites)
				.disabled(model.config.cipherSuites == .none)
		}
	}

	private var proxyPane: some View {
		pane(ServerPropertiesStrings.Navigation.proxyServer) {
			Picker("Type of Proxy", selection: $model.config.proxyType) {
				Text("None").tag(IRCConnectionProxyType.none)
				Text("Automatic").tag(IRCConnectionProxyType.automatic)
				Text("SOCKS 5 Proxy").tag(IRCConnectionProxyType.socks5)
				Text("HTTP Proxy (Anonymous)").tag(IRCConnectionProxyType.HTTP)
				Text("Tor Anonymity Network").tag(IRCConnectionProxyType.tor)
			}
			if ServerPropertiesModel.proxyTypeUsesAddress(model.config.proxyType) {
				Form {
					TextField("Address", text: $model.proxyAddress)
					TextField("Port", text: $model.proxyPort)
					if model.config.proxyType == .socks5 {
						TextField("Username", text: $model.proxyUsername)
						SecureField("Password", text: $model.proxyPassword)
					}
				}
			} else if model.config.proxyType == .automatic {
				Button("Open System Settings") {
					if let url = Self.networkProxySettingsURL {
						openURL(url)
					}
				}
			} else if model.config.proxyType == .tor {
				Text("Tor Browser must be running before connecting.").foregroundStyle(.secondary)
			}
		}
	}

	private var floodPane: some View {
		pane(ServerPropertiesStrings.Navigation.floodControl) {
			LabeledContent("Number of commands", value: String(model.config.floodControlMaximumMessages))
			Slider(value: uintBinding(\.floodControlMaximumMessages), in: 1 ... 60, step: 1)
			LabeledContent("Number of seconds", value: String(model.config.floodControlDelayTimerInterval))
			Slider(value: uintBinding(\.floodControlDelayTimerInterval), in: 1 ... 60, step: 1)
		}
	}

	private var redundancyPane: some View {
		pane(ServerPropertiesStrings.Navigation.redundancy) {
			Toggle("Reconnect after disconnect", isOn: $model.config.autoReconnect)
			Toggle("Disconnect when the computer sleeps", isOn: $model.config.autoSleepModeDisconnect)
			Toggle("Disconnect when reachability changes", isOn: $model.config.performDisconnectOnReachabilityChange)
			Button("Modify Alternate Servers", action: actions.editEndpoints)
		}
	}

	private func pane(_ title: String, @ViewBuilder content: () -> some View) -> some View {
		VStack(alignment: .leading, spacing: 16) {
			Text(verbatim: title).font(.title2).fontWeight(.semibold)
			content()
		}.frame(maxWidth: .infinity, alignment: .topLeading)
	}

	private func listButtons(add: @escaping () -> Void, edit: @escaping () -> Void, delete: @escaping () -> Void,
	                         selectionExists: Bool) -> some View
	{
		HStack {
			Button(action: add) { Image(systemName: "plus") }
			Button(action: edit) { Image(systemName: "pencil") }.disabled(!selectionExists)
			Button(role: .destructive, action: delete) { Image(systemName: "minus") }.disabled(!selectionExists)
			Spacer()
		}.buttonStyle(.borderless)
	}

	private func fingerprint(_ label: String, _ value: String) -> some View {
		HStack {
			LabeledContent(label, value: value)
			Button("Copy") { actions.copyCertificateFingerprint(value) }
				.disabled(model.config.identityClientSideCertificate == nil)
		}
	}

	private func optionalBinding(_ keyPath: WritableKeyPath<ClientConfig, String?>) -> Binding<String> {
		Binding(
			get: { model.config[keyPath: keyPath] ?? "" },
			set: { model.config[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
		)
	}

	private var warningBinding: Binding<Bool> {
		Binding(get: { !model.config.hideAutojoinDelayedWarnings },
		        set: { model.config.hideAutojoinDelayedWarnings = !$0 })
	}

	private func channelAutoJoinBinding(_ identifier: String) -> Binding<Bool> {
		Binding(
			get: { model.config.channelList.first { $0.uniqueIdentifier == identifier }?.autoJoin ?? false },
			set: { value in
				guard let index = model.config.channelList.firstIndex(where: { $0.uniqueIdentifier == identifier })
				else { return }
				model.config.channelList[index].autoJoin = value
			}
		)
	}

	private func uintBinding(_ keyPath: WritableKeyPath<ClientConfig, UInt>) -> Binding<Double> {
		Binding(get: { Double(model.config[keyPath: keyPath]) },
		        set: { model.config[keyPath: keyPath] = UInt($0) })
	}
}
