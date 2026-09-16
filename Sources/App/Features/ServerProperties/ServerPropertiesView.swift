/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import SwiftUI

/// What the pencil and minus buttons under one of the sheet's lists do, and the
/// names its icon-only buttons say out loud. Also what a row's context menu and
/// the Delete key reach.
struct ServerPropertiesSelectedEntryActions {
	let editLabel: String
	let edit: () -> Void
	let removeLabel: String
	let remove: () -> Void
}

/// A list whose plus button adds the one kind of thing the list holds.
struct ServerPropertiesListActions {
	let addLabel: String
	let add: () -> Void
	let selected: ServerPropertiesSelectedEntryActions
}

/// The Address Book list, whose plus button is a menu because an entry is
/// either an ignore or a tracked user.
struct ServerPropertiesAddressBookActions {
	let addLabel: String
	let addIgnore: () -> Void
	let addTracking: () -> Void
	let selected: ServerPropertiesSelectedEntryActions
}

struct ServerPropertiesCertificateActions {
	let choose: () -> Void
	let reset: () -> Void
	let copyNickServCommand: (String) -> Void
}

struct ServerPropertiesActions {
	let submit: () -> Void
	let cancel: () -> Void
	/// Continue on the template step a new connection opens on.
	let applyTemplate: () -> Void
	let editEndpoints: () -> Void
	let channels: ServerPropertiesListActions
	let highlights: ServerPropertiesListActions
	let addressBook: ServerPropertiesAddressBookActions
	let certificate: ServerPropertiesCertificateActions
}

struct ServerPropertiesView: View {
	@Bindable var model: ServerPropertiesModel
	@Environment(\.openURL) private var openURL
	let actions: ServerPropertiesActions

	private static let networkProxySettingsURL = URL(
		string: "x-apple.systempreferences:com.apple.Network-Settings.extension?Proxies"
	)

	/* The pickers list their options in a deliberate order rather than the
	 declaration order of the enums, so each carries its own array. */
	private static let addressTypes: [ConnectionAddressType] = [.default, .v4, .v6]
	private static let cipherSuiteCollections: [CipherSuiteCollection] = [
		.default, .mozilla2017, .mozilla2015, .none,
	]
	private static let proxyTypes: [ConnectionProxyType] = [.none, .automatic, .socks5, .HTTP, .tor]

	/// Built once for the process: the list is the same for every sheet, and
	/// sorting several hundred encoding names is not work to repeat per view.
	private static let encodings: [(value: UInt, title: String)] = {
		let values = String.Encoding.supportedEncodingsByTitle(favoringUTF8: false)
		return values.map { ($0.value.uintValue, $0.key) }.sorted { $0.title < $1.title }
	}()

	var body: some View {
		Group {
			if let picker = model.templatePicker {
				ServerTemplatePickerView(model: model, picker: picker, actions: actions)
			} else {
				form
			}
		}
		/* The sheet takes its size from here and nowhere else. The infinite
		 maxima are what let the user drag its edges: without them the content
		 refuses to grow and the sheet has nothing to resize into. */
		.disabled(model.isSaving)
		.frame(
			minWidth: 820,
			idealWidth: 900,
			maxWidth: .infinity,
			minHeight: 590,
			idealHeight: 650,
			maxHeight: .infinity
		)
		/* The sheet's keychain secrets are read once as it opens, and the
		 certificate's description again whenever a different one is chosen. */
		.task { await model.loadSecrets() }
		.task(id: model.config.identityClientSideCertificate) { await model.loadCertificate() }
	}

	private var form: some View {
		VStack(spacing: 0) {
			NavigationSplitView {
				List(selection: $model.selection) {
					Section(ServerPropertiesStrings.Navigation.connection) {
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
					}
				}
				.listStyle(.sidebar)
				.navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
			} detail: {
				selectedPane
			}
			/* A sheet has no toolbar to put a sidebar toggle in, so the one the
			 split view adds by default lands on top of the section list. The
			 list is always visible here anyway. */
			.toolbar(removing: .sidebarToggle)

			Divider()
			HStack {
				if let message = model.validationMessage {
					ValidationMessageLabel(message)
				}
				Spacer()
				Button(PromptStrings.Action.cancel, action: actions.cancel)
					.keyboardShortcut(.cancelAction)
				Button(PromptStrings.Action.save, action: actions.submit)
					.keyboardShortcut(.defaultAction)
					.disabled(model.validationMessage != nil)
			}
			.padding(12)
		}
	}

	@ViewBuilder
	private var selectedPane: some View {
		switch model.selection {
		case .general: generalPane
		case .identity: identityPane
		case .autojoin: channelPane
		case .highlights: highlightPane
		case .addressBook: addressBookPane
		case .connectCommands: commandsPane
		case .disconnectMessages: messagesPane
		case .encoding: encodingPane
		case .zncBouncer: zncPane
		case .clientCertificate: certificatePane
		case .networkSocket: socketPane
		case .proxyServer: proxyPane
		case .floodControl: floodPane
		}
	}

	private func navigationRow(
		_ selection: ServerPropertiesSelection,
		_ title: String,
		_ symbol: String
	) -> some View {
		Label(title, systemImage: symbol).tag(selection)
	}
}

// MARK: - Panes

private extension ServerPropertiesView {
	var generalPane: some View {
		pane(ServerPropertiesStrings.Navigation.general) {
			Form {
				Section {
					TextField(ServerPropertiesStrings.General.connectionName, text: $model.config.connectionName)
					TextField(ServerPropertiesStrings.General.serverAddress, text: $model.serverAddress)
						/* The suggestion rows complete to a network's name, and the
						 model turns that name into the network's address, port and
						 TLS state. A sighted person sees the list drop down; the
						 hint is what says it is there. */
						.textInputSuggestions(model.serverAddressSuggestions, id: \.networkName) { network in
							Text(verbatim: network.networkName)
								.textInputCompletion(network.networkName)
						}
						.accessibilityHint(ServerPropertiesStrings.General.serverAddressNetworkHint)
						.onChange(of: model.serverAddress) { model.serverAddressTextDidChange() }
					TextField(ServerPropertiesStrings.General.serverPort, text: $model.serverPort)
					Toggle(ServerPropertiesStrings.General.connectSecurely, isOn: $model.primaryServerIsSecured)
					SecureField(ServerPropertiesStrings.General.serverPassword, text: $model.serverPassword)
				} footer: {
					Text(verbatim: ServerPropertiesStrings.General.serverPasswordHelp)
				}

				Section {
					Button(ServerPropertiesStrings.General.modifyAlternateServers, action: actions.editEndpoints)
				}

				Section {
					Toggle(ServerPropertiesStrings.General.connectOnLaunch, isOn: $model.config.autoConnect)
					Toggle(
						ServerPropertiesStrings.General.reconnectAfterDisconnect,
						isOn: $model.config.autoReconnect
					)
					Toggle(
						ServerPropertiesStrings.General.disconnectWhenComputerSleeps,
						isOn: $model.config.autoSleepModeDisconnect
					)
				}
			}
			.formStyle(.grouped)
		}
	}

	var identityPane: some View {
		pane(ServerPropertiesStrings.Navigation.identity) {
			Form {
				Section {
					TextField(ServerPropertiesStrings.Identity.nickname, text: $model.config.nickname)
					TextField(
						ServerPropertiesStrings.Identity.awayNickname,
						text: optionalBinding(\.awayNickname)
					)
					TextField(
						ServerPropertiesStrings.Identity.alternativeNicknames,
						text: $model.alternateNicknames
					)
					TextField(ServerPropertiesStrings.Identity.username, text: $model.config.username)
					TextField(ServerPropertiesStrings.Identity.realName, text: $model.config.realName)
					TextField(
						ServerPropertiesStrings.Identity.ctcpVersionReply,
						text: optionalBinding(\.ctcpVersionReply)
					)
				}

				Section {
					SecureField(
						ServerPropertiesStrings.Identity.nicknamePassword,
						text: $model.nicknamePassword
					)
					/* The onboarding network picker was the only place this
					 could be chosen, so a connection made any other way was
					 stuck with the default until someone hand-edited the
					 stored configuration. */
					Toggle(ServerPropertiesStrings.Identity.signInWithSASL, isOn: $model.config.usesSASL)
					Toggle(
						ServerPropertiesStrings.Identity.disconnectOnSASLFailure,
						isOn: $model.config.disconnectOnSASLFailure
					)
					Toggle(
						ServerPropertiesStrings.Identity.autojoinWaitsForNickServ,
						isOn: $model.config.autojoinWaitsForNickServ
					)
				} footer: {
					Text(verbatim: ServerPropertiesStrings.Identity.nicknamePasswordHelp)
				}

				Section {
					Toggle(
						ServerPropertiesStrings.Identity.warnWhenChannelsCannotBeJoined,
						isOn: warningBinding
					)
				}
			}
			.formStyle(.grouped)
		}
	}

	var channelPane: some View {
		pane(ServerPropertiesStrings.Navigation.channelList) {
			List(selection: $model.selectedChannelID) {
				ForEach(model.displayedChannels, id: \.uniqueIdentifier) { channel in
					HStack {
						Toggle(
							ChannelPropertiesStrings.joinOnConnect,
							isOn: channelAutoJoinBinding(channel.uniqueIdentifier)
						).labelsHidden()
						Text(verbatim: channel.channelName)
						Spacer()
						if model.channelHasSecretKey(channel) {
							Image(systemName: "key.fill")
								.accessibilityLabel(ChannelPropertiesStrings.passwordLabel)
						}
					}.tag(channel.uniqueIdentifier)
				}
			}
			.listCommands(actions.channels.selected, selection: $model.selectedChannelID)

			listButtons(actions.channels, hasSelection: model.selectedChannelID != nil)
		}
	}

	var highlightPane: some View {
		pane(ServerPropertiesStrings.Navigation.highlights) {
			List(selection: $model.selectedHighlightID) {
				ForEach(model.config.highlightList, id: \.uniqueIdentifier) { entry in
					VStack(alignment: .leading) {
						Text(verbatim: entry.matchKeyword)
						Text(verbatim: ServerPropertiesStrings.Highlight.matchType(
							isExcluded: entry.matchIsExcluded
						))
						.font(.caption).foregroundStyle(.secondary)
					}.tag(entry.uniqueIdentifier)
				}
			}
			.listCommands(actions.highlights.selected, selection: $model.selectedHighlightID)

			listButtons(actions.highlights, hasSelection: model.selectedHighlightID != nil)
		}
	}

	var addressBookPane: some View {
		pane(ServerPropertiesStrings.Navigation.addressBook) {
			List(selection: $model.selectedAddressBookEntryID) {
				ForEach(model.config.ignoreList, id: \.uniqueIdentifier) { entry in
					VStack(alignment: .leading) {
						Text(verbatim: entry.hostmask)
						Text(verbatim: ServerPropertiesStrings.AddressBook.entryType(entry.entryType))
							.font(.caption).foregroundStyle(.secondary)
					}.tag(entry.uniqueIdentifier)
				}
			}
			.listCommands(actions.addressBook.selected, selection: $model.selectedAddressBookEntryID)

			HStack {
				Menu {
					addressBookAddButtons
				} label: {
					Image(systemName: "plus")
				}
				.menuIndicator(.hidden)
				.help(Text(verbatim: actions.addressBook.addLabel))
				.accessibilityLabel(Text(verbatim: actions.addressBook.addLabel))

				editAndRemoveButtons(
					actions.addressBook.selected,
					hasSelection: model.selectedAddressBookEntryID != nil
				)
				Spacer()
			}
			.buttonStyle(.borderless)
		}
	}

	@ViewBuilder
	var addressBookAddButtons: some View {
		Button(
			ServerPropertiesStrings.AddressBookActions.addIgnoreEntry,
			action: actions.addressBook.addIgnore
		)
		Button(
			ServerPropertiesStrings.AddressBookActions.addTrackingEntry,
			action: actions.addressBook.addTracking
		)
	}

	var commandsPane: some View {
		pane(ServerPropertiesStrings.Navigation.connectCommands) {
			Form {
				Section(ServerPropertiesStrings.ConnectCommands.heading) {
					TextEditor(text: $model.connectCommands)
						.font(.system(.body, design: .monospaced))
						.frame(minHeight: 180)
						.accessibilityLabel(ServerPropertiesStrings.ConnectCommands.heading)
				}

				Section {
					Toggle(
						ServerPropertiesStrings.ConnectCommands.setInvisibleMode,
						isOn: $model.config.setInvisibleModeOnConnect
					)
					Toggle(
						ServerPropertiesStrings.ConnectCommands.runSilently,
						isOn: $model.config.runConnectCommandsSilently
					)
					Toggle(
						ServerPropertiesStrings.ConnectCommands.autojoinWaitsForConnectCommands,
						isOn: $model.config.autojoinWaitsForConnectCommands
					)
					Stepper(
						value: $model.config.autojoinDelayAfterConnectCommands,
						in: 0 ... ClientConfigDefaults.maximumAutojoinConnectCommandDelay,
						step: 1
					) {
						Text(verbatim: ServerPropertiesStrings.ConnectCommands.autojoinDelay(
							seconds: Int(model.config.autojoinDelayAfterConnectCommands)
						))
					}
					.disabled(model.config.autojoinWaitsForConnectCommands == false)
				} footer: {
					Text(verbatim: ServerPropertiesStrings.ConnectCommands.identificationExplanation)
				}
			}
			.formStyle(.grouped)
		}
	}

	var messagesPane: some View {
		pane(ServerPropertiesStrings.Navigation.messages) {
			Form {
				Section {
					TextField(
						ServerPropertiesStrings.LeavingMessages.normal,
						text: $model.config.normalLeavingComment
					)
					TextField(
						ServerPropertiesStrings.LeavingMessages.sleepMode,
						text: $model.config.sleepModeLeavingComment
					)
				}
			}
			.formStyle(.grouped)
		}
	}

	var encodingPane: some View {
		pane(ServerPropertiesStrings.Navigation.encoding) {
			Form {
				Section {
					Picker(ServerPropertiesStrings.Encoding.primary, selection: $model.config.primaryEncoding) {
						ForEach(Self.encodings, id: \.value) { Text(verbatim: $0.title).tag($0.value) }
					}
					Picker(ServerPropertiesStrings.Encoding.fallback, selection: $model.config.fallbackEncoding) {
						ForEach(Self.encodings, id: \.value) { Text(verbatim: $0.title).tag($0.value) }
					}
				}
			}
			.formStyle(.grouped)
		}
	}

	var zncPane: some View {
		pane(ServerPropertiesStrings.Navigation.zncBouncer) {
			Form {
				Section {
					Toggle(
						ServerPropertiesStrings.ZNC.ignoreConfiguredAutojoin,
						isOn: $model.config.zncIgnoreConfiguredAutojoin
					)
					Toggle(
						ServerPropertiesStrings.ZNC.ignorePlaybackNotifications,
						isOn: $model.config.zncIgnorePlaybackNotifications
					)
					Toggle(
						ServerPropertiesStrings.ZNC.onlyPlaybackLatest,
						isOn: $model.config.zncOnlyPlaybackLatest
					)
				} footer: {
					Text(verbatim: ServerPropertiesStrings.ZNC.versionNote)
				}
			}
			.formStyle(.grouped)
		}
	}

	var certificatePane: some View {
		pane(ServerPropertiesStrings.Navigation.clientCertificate) {
			Form {
				Section {
					if let certificate = model.certificate {
						LabeledContent(
							ServerPropertiesStrings.Certificate.name,
							value: certificate.commonName
						)
					} else {
						Text(verbatim: ServerPropertiesStrings.Certificate.noneSelected)
							.foregroundStyle(.secondary)
					}
					HStack {
						Button(
							ServerPropertiesStrings.Certificate.select,
							action: actions.certificate.choose
						)
						Button(
							ServerPropertiesStrings.Certificate.reset,
							role: .destructive,
							action: actions.certificate.reset
						)
						.disabled(model.certificate == nil)
					}
				} footer: {
					Text(verbatim: ServerPropertiesStrings.Certificate.chooseExplanation)
				}

				if let certificate = model.certificate {
					Section {
						fingerprint(ServerPropertiesStrings.Certificate.fingerprintSHA512, certificate.sha512)
						fingerprint(ServerPropertiesStrings.Certificate.fingerprintSHA256, certificate.sha256)
						fingerprint(ServerPropertiesStrings.Certificate.fingerprintSHA1, certificate.sha1)
					} footer: {
						Text(verbatim: ServerPropertiesStrings.Certificate.fingerprintHelp)
					}
				}
			}
			.formStyle(.grouped)
		}
	}

	var socketPane: some View {
		pane(ServerPropertiesStrings.Navigation.networkSocket) {
			Form {
				Section {
					Picker(ServerPropertiesStrings.Socket.connectUsing, selection: $model.config.addressType) {
						ForEach(Self.addressTypes, id: \.self) { addressType in
							Text(verbatim: ServerPropertiesStrings.Socket.addressType(addressType)).tag(addressType)
						}
					}
					.pickerStyle(.radioGroup)
				}

				Section {
					Toggle(
						ServerPropertiesStrings.Socket.validateCertificateChain,
						isOn: $model.config.validateServerCertificateChain
					)
					Toggle(ServerPropertiesStrings.Socket.performPongTimer, isOn: $model.config.performPongTimer)
					Toggle(
						ServerPropertiesStrings.Socket.disconnectOnPongTimer,
						isOn: $model.config.performDisconnectOnPongTimer
					)
					Toggle(
						ServerPropertiesStrings.Socket.disconnectOnReachabilityChange,
						isOn: $model.config.performDisconnectOnReachabilityChange
					)
				}

				Section {
					Picker(ServerPropertiesStrings.CipherSuites.label, selection: $model.config.cipherSuites) {
						ForEach(Self.cipherSuiteCollections, id: \.self) { collection in
							Text(verbatim: ServerPropertiesStrings.CipherSuites.collectionName(collection))
								.tag(collection)
						}
					}
					if model.config.cipherSuites != .none {
						cipherSuiteList
					}
				} footer: {
					if model.config.cipherSuites != .none {
						Text(verbatim: ServerPropertiesStrings.CipherSuites.listExplanation(
							collectionName: ServerPropertiesStrings.CipherSuites
								.collectionName(model.config.cipherSuites)
						))
					}
				}
			}
			.formStyle(.grouped)
		}
	}

	/// The suites of the chosen collection, in the pane rather than in an alert
	/// whose body was a hundred lines of proportional text.
	var cipherSuiteList: some View {
		DisclosureGroup(ServerPropertiesStrings.CipherSuites.suiteList) {
			VStack(alignment: .leading, spacing: 2) {
				ForEach(
					SecureTransportSupport.descriptions(
						forCipherListCollection: model.config.cipherSuites,
						withProtocol: true
					),
					id: \.self
				) { suite in
					Text(verbatim: suite).textSelection(.enabled)
				}
			}
			.font(.system(.caption, design: .monospaced))
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.top, 4)
		}
	}

	var proxyPane: some View {
		pane(ServerPropertiesStrings.Navigation.proxyServer) {
			Form {
				Section {
					Picker(ServerPropertiesStrings.Proxy.type, selection: $model.config.proxyType) {
						ForEach(Self.proxyTypes, id: \.self) { proxyType in
							Text(verbatim: ServerPropertiesStrings.Proxy.typeName(proxyType)).tag(proxyType)
						}
					}
				}

				if ServerPropertiesModel.proxyTypeUsesAddress(model.config.proxyType) {
					Section {
						TextField(ServerPropertiesStrings.Proxy.address, text: $model.proxyAddress)
						TextField(ServerPropertiesStrings.Proxy.port, text: $model.proxyPort)
						if model.config.proxyType == .socks5 {
							TextField(ServerPropertiesStrings.Proxy.username, text: $model.proxyUsername)
							SecureField(ServerPropertiesStrings.Proxy.password, text: $model.proxyPassword)
						}
					} footer: {
						if model.config.proxyType == .socks5 {
							Text(verbatim: ServerPropertiesStrings.Proxy.passwordHelp)
						}
					}
				} else if model.config.proxyType == .automatic {
					Section {
						Button(ServerPropertiesStrings.Proxy.openSystemSettings) {
							if let url = Self.networkProxySettingsURL {
								openURL(url)
							}
						}
					}
				} else if model.config.proxyType == .tor {
					Section {
						Text(verbatim: ServerPropertiesStrings.Proxy.torBrowserNote)
							.foregroundStyle(.secondary)
					}
				}
			}
			.formStyle(.grouped)
		}
	}

	var floodPane: some View {
		pane(ServerPropertiesStrings.Navigation.floodControl) {
			Form {
				Section {
					slider(
						ServerPropertiesStrings.FloodControl.messageCount,
						value: uintBinding(\.floodControlMaximumMessages),
						current: Int(model.config.floodControlMaximumMessages)
					)
					slider(
						ServerPropertiesStrings.FloodControl.interval,
						value: uintBinding(\.floodControlDelayTimerInterval),
						current: Int(model.config.floodControlDelayTimerInterval)
					)
				}
			}
			.formStyle(.grouped)
		}
	}

	// MARK: - Building blocks

	func pane(_ title: String, @ViewBuilder content: () -> some View) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			Text(verbatim: title)
				.font(.title2)
				.fontWeight(.semibold)
				.padding([.horizontal, .top], 20)
			content()
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
	}

	/// Every button here is an icon and nothing else, so each one carries the
	/// name of what it does — as a help tag for the pointer and as a label for
	/// VoiceOver.
	func listButtons(_ actions: ServerPropertiesListActions, hasSelection: Bool) -> some View {
		HStack {
			Button(action: actions.add) { Image(systemName: "plus") }
				.help(Text(verbatim: actions.addLabel))
				.accessibilityLabel(Text(verbatim: actions.addLabel))
			editAndRemoveButtons(actions.selected, hasSelection: hasSelection)
			Spacer()
		}
		.buttonStyle(.borderless)
		.padding(.horizontal, 20)
		.padding(.bottom, 12)
	}

	@ViewBuilder
	func editAndRemoveButtons(
		_ actions: ServerPropertiesSelectedEntryActions,
		hasSelection: Bool
	) -> some View {
		Button(action: actions.edit) { Image(systemName: "pencil") }
			.disabled(hasSelection == false)
			.help(Text(verbatim: actions.editLabel))
			.accessibilityLabel(Text(verbatim: actions.editLabel))
		Button(role: .destructive, action: actions.remove) { Image(systemName: "minus") }
			.disabled(hasSelection == false)
			.help(Text(verbatim: actions.removeLabel))
			.accessibilityLabel(Text(verbatim: actions.removeLabel))
	}

	func fingerprint(_ label: String, _ value: String) -> some View {
		LabeledContent(label) {
			HStack {
				Text(verbatim: value)
					.font(.system(.caption, design: .monospaced))
					.textSelection(.enabled)
					.lineLimit(1)
					.truncationMode(.middle)
				Button(ServerPropertiesStrings.Certificate.copyNickServCommand) {
					actions.certificate.copyNickServCommand(value)
				}
				.help(Text(verbatim: ServerPropertiesStrings.Certificate.copyNickServCommand(forDigest: label)))
				.accessibilityLabel(
					Text(verbatim: ServerPropertiesStrings.Certificate.copyNickServCommand(forDigest: label))
				)
			}
		}
	}

	func slider(_ label: String, value: Binding<Double>, current: Int) -> some View {
		LabeledContent(label) {
			HStack {
				Slider(value: value, in: 1 ... 60, step: 1)
					.accessibilityLabel(label)
				Text(current, format: .number)
					.monospacedDigit()
					.frame(width: 28, alignment: .trailing)
			}
		}
	}

	func optionalBinding(_ keyPath: WritableKeyPath<ClientConfig, String?>) -> Binding<String> {
		Binding(
			get: { model.config[keyPath: keyPath] ?? "" },
			set: { model.config[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
		)
	}

	var warningBinding: Binding<Bool> {
		Binding(get: { model.config.hideAutojoinDelayedWarnings == false },
		        set: { model.config.hideAutojoinDelayedWarnings = $0 == false })
	}

	func channelAutoJoinBinding(_ identifier: String) -> Binding<Bool> {
		Binding(
			get: { model.config.channelList.first { $0.uniqueIdentifier == identifier }?.autoJoin ?? false },
			set: { value in
				guard let index = model.config.channelList.firstIndex(where: { $0.uniqueIdentifier == identifier })
				else { return }
				model.config.channelList[index].autoJoin = value
			}
		)
	}

	func uintBinding(_ keyPath: WritableKeyPath<ClientConfig, UInt>) -> Binding<Double> {
		Binding(get: { Double(model.config[keyPath: keyPath]) },
		        set: { model.config[keyPath: keyPath] = UInt($0) })
	}
}

private extension View {
	/** The keyboard and context menu every one of the sheet's lists answers to.

	 The three lists were selection and two buttons and nothing else: Delete did
	 nothing, a secondary click offered nothing, and opening a row meant finding
	 the pencil. `primaryAction` is the double-click and Return at once. */
	func listCommands(
		_ actions: ServerPropertiesSelectedEntryActions,
		selection: Binding<String?>
	) -> some View {
		onDeleteCommand(perform: actions.remove)
			.contextMenu(forSelectionType: String.self) { identifiers in
				Button(actions.editLabel) {
					selection.wrappedValue = identifiers.first
					actions.edit()
				}
				.disabled(identifiers.count != 1)
				Divider()
				Button(actions.removeLabel, role: .destructive) {
					selection.wrappedValue = identifiers.first
					actions.remove()
				}
				.disabled(identifiers.isEmpty)
			} primaryAction: { identifiers in
				guard identifiers.count == 1 else { return }
				selection.wrappedValue = identifiers.first
				actions.edit()
			}
	}
}
