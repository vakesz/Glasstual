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
	let editLabel: LocalizedStringResource
	let edit: () -> Void
	let removeLabel: LocalizedStringResource
	let remove: () -> Void
}

/// A list whose plus button adds the one kind of thing the list holds.
struct ServerPropertiesListActions {
	let addLabel: LocalizedStringResource
	let add: () -> Void
	let selected: ServerPropertiesSelectedEntryActions
}

/// The Address Book list, whose plus button is a menu because an entry is
/// either an ignore or a tracked user.
struct ServerPropertiesAddressBookActions {
	let addLabel: LocalizedStringResource
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
					Section(.ServerProperties.navigationSectionConnection) {
						navigationRow(.general, .ServerProperties.serverPropertiesNavigationMenuGeneral, "network")
						navigationRow(.identity, .ServerProperties.serverPropertiesNavigationMenuIdentity, "person.crop.circle")
						navigationRow(.autojoin, .ServerProperties.channelList, "number")
						navigationRow(.highlights, .ServerProperties.serverPropertiesNavigationMenuHighlights, "highlighter")
						navigationRow(.addressBook, .ServerProperties.addressBook, "person.2")
						navigationRow(.connectCommands, .ServerProperties.connectCommands, "terminal")
						navigationRow(.disconnectMessages, .ServerProperties.serverPropertiesNavigationMenuMessages, "text.bubble")
						navigationRow(.encoding, .ServerProperties.serverPropertiesNavigationMenuEncoding, "character.book.closed")
					}
					Section(.ServerProperties.vendorSpecific) {
						navigationRow(.zncBouncer, .ServerProperties.zncBouncer, "server.rack")
					}
					Section(.ServerProperties.serverPropertiesNavigationMenuAdvanced) {
						navigationRow(
							.clientCertificate,
							.ServerProperties.clientCertificate,
							"checkmark.shield"
						)
						navigationRow(
							.networkSocket,
							.ServerProperties.networkSocket,
							"cable.connector"
						)
						navigationRow(
							.proxyServer,
							.ServerProperties.proxyServer,
							"arrow.triangle.branch"
						)
						navigationRow(.floodControl, .ServerProperties.floodControl, "speedometer")
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
		_ title: LocalizedStringResource,
		_ symbol: String
	) -> some View {
		Label(title, systemImage: symbol).tag(selection)
	}
}

// MARK: - Panes

private extension ServerPropertiesView {
	var generalPane: some View {
		pane(.ServerProperties.serverPropertiesNavigationMenuGeneral) {
			Form {
				Section {
					TextField(.ServerProperties.connectionName, text: $model.config.connectionName)
					TextField(.ServerProperties.serverAddress, text: $model.serverAddress)
						/* The suggestion rows complete to a network's name, and the
						 model turns that name into the network's address, port and
						 TLS state. A sighted person sees the list drop down; the
						 hint is what says it is there. */
						.textInputSuggestions(model.serverAddressSuggestions, id: \.networkName) { network in
							Text(verbatim: network.networkName)
								.textInputCompletion(network.networkName)
						}
						.accessibilityHint(.ServerProperties.serverAddressNetworkHint)
						.onChange(of: model.serverAddress) { model.serverAddressTextDidChange() }
					TextField(.ServerProperties.serverPort, text: $model.serverPort)
					Toggle(.ServerProperties.connectSecurely, isOn: $model.primaryServerIsSecured)
					SecureField(.ServerProperties.serverPassword, text: $model.serverPassword)
				} footer: {
					Text(.ServerProperties.serverPasswordHelp)
				}

				Section {
					Button(.ServerProperties.modifyAlternateServers, action: actions.editEndpoints)
				}

				Section {
					Toggle(.ServerProperties.connectWhenGlasstualOpens, isOn: $model.config.autoConnect)
					Toggle(
						.ServerProperties.reconnectAfterDisconnect,
						isOn: $model.config.autoReconnect
					)
					Toggle(
						.ServerProperties.disconnectWhenComputerSleeps,
						isOn: $model.config.autoSleepModeDisconnect
					)
				}
			}
			.formStyle(.grouped)
		}
	}

	var identityPane: some View {
		pane(.ServerProperties.serverPropertiesNavigationMenuIdentity) {
			Form {
				Section {
					TextField(.ServerProperties.nickname, text: $model.config.nickname)
					TextField(
						.ServerProperties.awayNickname,
						text: optionalBinding(\.awayNickname)
					)
					TextField(
						.ServerProperties.alternativeNicknames,
						text: $model.alternateNicknames
					)
					TextField(.ServerProperties.username, text: $model.config.username)
					TextField(.ServerProperties.realName, text: $model.config.realName)
					TextField(
						.ServerProperties.ctcpVersionReply,
						text: optionalBinding(\.ctcpVersionReply)
					)
				}

				Section {
					SecureField(
						.ServerProperties.nickservOrSaslPassword,
						text: $model.nicknamePassword
					)
					/* The onboarding network picker was the only place this
					 could be chosen, so a connection made any other way was
					 stuck with the default until someone hand-edited the
					 stored configuration. */
					Toggle(.ServerProperties.signInWithSasl, isOn: $model.config.usesSASL)
					Toggle(
						.ServerProperties.disconnectOnSaslFailure,
						isOn: $model.config.disconnectOnSASLFailure
					)
					Toggle(
						.ServerProperties.autojoinWaitsForNickserv,
						isOn: $model.config.autojoinWaitsForNickServ
					)
				} footer: {
					Text(.ServerProperties.nicknamePasswordHelp)
				}

				Section {
					Toggle(
						.ServerProperties.warnWhenChannelsCannotBeJoined,
						isOn: warningBinding
					)
				}
			}
			.formStyle(.grouped)
		}
	}

	var channelPane: some View {
		pane(.ServerProperties.channelList) {
			List(selection: $model.selectedChannelID) {
				ForEach(model.displayedChannels, id: \.uniqueIdentifier) { channel in
					HStack {
						Toggle(
							.ChannelProperties.joinOnConnect,
							isOn: channelAutoJoinBinding(channel.uniqueIdentifier)
						).labelsHidden()
						Text(verbatim: channel.channelName)
						Spacer()
						if model.channelHasSecretKey(channel) {
							Image(systemName: "key.fill")
								.accessibilityLabel(.ChannelProperties.passwordLabel)
						}
					}.tag(channel.uniqueIdentifier)
				}
			}
			.listCommands(actions.channels.selected, selection: $model.selectedChannelID)

			listButtons(actions.channels, hasSelection: model.selectedChannelID != nil)
		}
	}

	var highlightPane: some View {
		pane(.ServerProperties.serverPropertiesNavigationMenuHighlights) {
			List(selection: $model.selectedHighlightID) {
				ForEach(model.config.highlightList, id: \.uniqueIdentifier) { entry in
					VStack(alignment: .leading) {
						Text(verbatim: entry.matchKeyword)
						Text(HighlightMatchBehavior(excludesMatches: entry.matchIsExcluded).title)
							.font(.caption).foregroundStyle(.secondary)
					}.tag(entry.uniqueIdentifier)
				}
			}
			.listCommands(actions.highlights.selected, selection: $model.selectedHighlightID)

			listButtons(actions.highlights, hasSelection: model.selectedHighlightID != nil)
		}
	}

	var addressBookPane: some View {
		pane(.ServerProperties.addressBook) {
			List(selection: $model.selectedAddressBookEntryID) {
				ForEach(model.config.ignoreList, id: \.uniqueIdentifier) { entry in
					VStack(alignment: .leading) {
						Text(verbatim: entry.hostmask)
						Text(entry.entryType.listTitle)
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
				.help(actions.addressBook.addLabel)
				.accessibilityLabel(actions.addressBook.addLabel)

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
			.ServerProperties.addUserIgnoreEntry,
			action: actions.addressBook.addIgnore
		)
		Button(
			.ServerProperties.addUserTrackingEntry,
			action: actions.addressBook.addTracking
		)
	}

	var commandsPane: some View {
		pane(.ServerProperties.connectCommands) {
			Form {
				Section(.ServerProperties.performCommandsOnConnect) {
					TextEditor(text: $model.connectCommands)
						.font(.system(.body, design: .monospaced))
						.frame(minHeight: 180)
						.accessibilityLabel(.ServerProperties.performCommandsOnConnect)
				}

				Section {
					Toggle(
						.ServerProperties.setInvisibleModeOnConnect,
						isOn: $model.config.setInvisibleModeOnConnect
					)
					Toggle(
						.ServerProperties.runCommandsSilently,
						isOn: $model.config.runConnectCommandsSilently
					)
					Toggle(
						.ServerProperties.autojoinWaitsForConnectCommands,
						isOn: $model.config.autojoinWaitsForConnectCommands
					)
					Stepper(
						value: $model.config.autojoinDelayAfterConnectCommands,
						in: 0 ... ClientConfigDefaults.maximumAutojoinConnectCommandDelay,
						step: 1
					) {
						Text(.ServerProperties.autojoinDelayAfterConnectCommands(
							Int(model.config.autojoinDelayAfterConnectCommands)
						))
					}
					.disabled(model.config.autojoinWaitsForConnectCommands == false)
				} footer: {
					Text(.ServerProperties.nickServConfirmationExplanation)
				}
			}
			.formStyle(.grouped)
		}
	}

	var messagesPane: some View {
		pane(.ServerProperties.serverPropertiesNavigationMenuMessages) {
			Form {
				Section {
					TextField(
						.ServerProperties.partAndQuitMessage,
						text: $model.config.normalLeavingComment
					)
					TextField(
						.ServerProperties.computerSleepQuitMessage,
						text: $model.config.sleepModeLeavingComment
					)
				}
			}
			.formStyle(.grouped)
		}
	}

	var encodingPane: some View {
		pane(.ServerProperties.serverPropertiesNavigationMenuEncoding) {
			Form {
				Section {
					Picker(.ServerProperties.encodingPrimary, selection: $model.config.primaryEncoding) {
						ForEach(Self.encodings, id: \.value) { Text(verbatim: $0.title).tag($0.value) }
					}
					Picker(.ServerProperties.encodingFallback, selection: $model.config.fallbackEncoding) {
						ForEach(Self.encodings, id: \.value) { Text(verbatim: $0.title).tag($0.value) }
					}
				}
			}
			.formStyle(.grouped)
		}
	}

	var zncPane: some View {
		pane(.ServerProperties.zncBouncer) {
			Form {
				Section {
					Toggle(
						.ServerProperties.zncIgnoreConfiguredAutojoin,
						isOn: $model.config.zncIgnoreConfiguredAutojoin
					)
					Toggle(
						.ServerProperties.zncIgnorePlaybackNotifications,
						isOn: $model.config.zncIgnorePlaybackNotifications
					)
					Toggle(
						.ServerProperties.zncOnlyPlaybackLatest,
						isOn: $model.config.zncOnlyPlaybackLatest
					)
				} footer: {
					Text(.ServerProperties.zncVersionNote)
				}
			}
			.formStyle(.grouped)
		}
	}

	var certificatePane: some View {
		pane(.ServerProperties.clientCertificate) {
			Form {
				Section {
					if let certificate = model.certificate {
						LabeledContent(
							.ServerProperties.certificateName,
							value: certificate.commonName
						)
					} else {
						Text(.ServerProperties.noCertificateSelected)
							.foregroundStyle(.secondary)
					}
					HStack {
						Button(
							.ServerProperties.selectCertificate,
							action: actions.certificate.choose
						)
						Button(
							.ServerProperties.resetCertificate,
							role: .destructive,
							action: actions.certificate.reset
						)
						.disabled(model.certificate == nil)
					}
				} footer: {
					Text(.ServerProperties.selectACertificateToSendWhen)
				}

				if let certificate = model.certificate {
					Section {
						fingerprint(.ServerProperties.sha512Fingerprint, certificate.sha512)
						fingerprint(.ServerProperties.sha256Fingerprint, certificate.sha256)
						fingerprint(.ServerProperties.sha1Fingerprint, certificate.sha1)
					} footer: {
						Text(.ServerProperties.certificateFingerprintHelp)
					}
				}
			}
			.formStyle(.grouped)
		}
	}

	var socketPane: some View {
		pane(.ServerProperties.networkSocket) {
			Form {
				Section {
					Picker(.ServerProperties.connectUsing, selection: $model.config.addressType) {
						ForEach(Self.addressTypes, id: \.self) { addressType in
							Text(addressType.title).tag(addressType)
						}
					}
					.pickerStyle(.radioGroup)
				}

				Section {
					Toggle(
						.ServerProperties.validateServerCertificateChain,
						isOn: $model.config.validateServerCertificateChain
					)
					Toggle(.ServerProperties.periodicallyPingTheServer, isOn: $model.config.performPongTimer)
					Toggle(
						.ServerProperties.disconnectOnPongTimer,
						isOn: $model.config.performDisconnectOnPongTimer
					)
					Toggle(
						.ServerProperties.disconnectOnReachabilityChange,
						isOn: $model.config.performDisconnectOnReachabilityChange
					)
				}

				Section {
					Picker(.ServerProperties.cipherSuitesLabel, selection: $model.config.cipherSuites) {
						ForEach(Self.cipherSuiteCollections, id: \.self) { collection in
							Text(collection.title).tag(collection)
						}
					}
					if model.config.cipherSuites != .none {
						cipherSuiteList
					}
				} footer: {
					if model.config.cipherSuites != .none {
						Text(.ServerProperties.includesTheFollowingCipherSuites(
							String(localized: model.config.cipherSuites.title)
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
		DisclosureGroup(.ServerProperties.viewCipherSuites) {
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
		pane(.ServerProperties.proxyServer) {
			Form {
				Section {
					Picker(.ServerProperties.proxyType, selection: $model.config.proxyType) {
						ForEach(Self.proxyTypes, id: \.self) { proxyType in
							Text(proxyType.title).tag(proxyType)
						}
					}
				}

				if ServerPropertiesModel.proxyTypeUsesAddress(model.config.proxyType) {
					Section {
						TextField(.ServerProperties.proxyAddress, text: $model.proxyAddress)
						TextField(.ServerProperties.proxyPort, text: $model.proxyPort)
						if model.config.proxyType == .socks5 {
							TextField(.ServerProperties.proxyUsername, text: $model.proxyUsername)
							SecureField(.ServerProperties.proxyPassword, text: $model.proxyPassword)
						}
					} footer: {
						if model.config.proxyType == .socks5 {
							Text(.ServerProperties.proxyPasswordHelp)
						}
					}
				} else if model.config.proxyType == .automatic {
					Section {
						Button(.ServerProperties.openSystemSettings) {
							if let url = Self.networkProxySettingsURL {
								openURL(url)
							}
						}
					}
				} else if model.config.proxyType == .tor {
					Section {
						Text(.ServerProperties.torBrowserNote)
							.foregroundStyle(.secondary)
					}
				}
			}
			.formStyle(.grouped)
		}
	}

	var floodPane: some View {
		pane(.ServerProperties.floodControl) {
			Form {
				Section {
					slider(
						.ServerProperties.floodControlMessageCount,
						value: uintBinding(\.floodControlMaximumMessages),
						current: Int(model.config.floodControlMaximumMessages)
					)
					slider(
						.ServerProperties.floodControlInterval,
						value: uintBinding(\.floodControlDelayTimerInterval),
						current: Int(model.config.floodControlDelayTimerInterval)
					)
				}
			}
			.formStyle(.grouped)
		}
	}

	// MARK: - Building blocks

	func pane(_ title: LocalizedStringResource, @ViewBuilder content: () -> some View) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			Text(title)
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
				.help(actions.addLabel)
				.accessibilityLabel(actions.addLabel)
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
			.help(actions.editLabel)
			.accessibilityLabel(actions.editLabel)
		Button(role: .destructive, action: actions.remove) { Image(systemName: "minus") }
			.disabled(hasSelection == false)
			.help(actions.removeLabel)
			.accessibilityLabel(actions.removeLabel)
	}

	func fingerprint(_ label: LocalizedStringResource, _ value: String) -> some View {
		LabeledContent(label) {
			HStack {
				Text(verbatim: value)
					.font(.system(.caption, design: .monospaced))
					.textSelection(.enabled)
					.lineLimit(1)
					.truncationMode(.middle)
				Button(.ServerProperties.copyNickservCommand) {
					actions.certificate.copyNickServCommand(value)
				}
				.help(.ServerProperties.copyNickservCommandFor(String(localized: label)))
				.accessibilityLabel(.ServerProperties.copyNickservCommandFor(String(localized: label)))
			}
		}
	}

	func slider(_ label: LocalizedStringResource, value: Binding<Double>, current: Int) -> some View {
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
