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

	/* The pickers list their options in a deliberate order rather than the
	 declaration order of the enums, so each carries its own array. */
	private static let addressTypes: [IRCConnectionAddressType] = [.default, .v4, .v6]
	private static let cipherSuiteCollections: [CipherSuiteCollection] = [
		.default, .mozilla2017, .mozilla2015, .none,
	]
	private static let proxyTypes: [IRCConnectionProxyType] = [.none, .automatic, .socks5, .HTTP, .tor]

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
				Button(PromptStrings.Action.save, action: actions.submit)
					.keyboardShortcut(.defaultAction)
			}
			.padding(12)
		}
		/* The sheet takes its size from here and nowhere else. The infinite
		 maxima are what let the user drag its edges: without them the content
		 refuses to grow and the sheet has nothing to resize into. */
		.frame(
			minWidth: 820,
			idealWidth: 900,
			maxWidth: .infinity,
			minHeight: 590,
			idealHeight: 650,
			maxHeight: .infinity
		)
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
				TextField(ServerPropertiesStrings.General.connectionName, text: $model.config.connectionName)
				TextField(ServerPropertiesStrings.General.serverAddress, text: $model.serverAddress)
				TextField(ServerPropertiesStrings.General.serverPort, text: $model.serverPort)
				SecureField(ServerPropertiesStrings.General.serverPassword, text: $model.serverPassword)
				Toggle(ServerPropertiesStrings.General.connectSecurely, isOn: $model.primaryServerIsSecured)
				Button(ServerPropertiesStrings.General.modifyAlternateServers, action: actions.editEndpoints)
				Divider()
				Toggle(ServerPropertiesStrings.General.connectOnLaunch, isOn: $model.config.autoConnect)
				Toggle(ServerPropertiesStrings.General.reconnectAfterDisconnect, isOn: $model.config.autoReconnect)
				Toggle(
					ServerPropertiesStrings.General.disconnectWhenComputerSleeps,
					isOn: $model.config.autoSleepModeDisconnect
				)
			}
		}
	}

	private var identityPane: some View {
		pane(ServerPropertiesStrings.Navigation.identity) {
			Form {
				TextField(ServerPropertiesStrings.Identity.nickname, text: $model.config.nickname)
				TextField(ServerPropertiesStrings.Identity.awayNickname, text: optionalBinding(\.awayNickname))
				TextField(ServerPropertiesStrings.Identity.alternativeNicknames, text: $model.alternateNicknames)
				TextField(ServerPropertiesStrings.Identity.username, text: $model.config.username)
				TextField(ServerPropertiesStrings.Identity.realName, text: $model.config.realName)
				TextField(ServerPropertiesStrings.Identity.ctcpVersionReply, text: optionalBinding(\.ctcpVersionReply))
				SecureField(ServerPropertiesStrings.Identity.nicknamePassword, text: $model.nicknamePassword)
				Divider()
				Toggle(
					ServerPropertiesStrings.Identity.autojoinWaitsForNickServ,
					isOn: $model.config.autojoinWaitsForNickServ
				)
				Toggle(ServerPropertiesStrings.Identity.warnWhenChannelsCannotBeJoined, isOn: warningBinding)
				Toggle(
					ServerPropertiesStrings.Identity.disconnectOnSASLFailure,
					isOn: $model.config.disconnectOnSASLFailure
				)
			}
		}
	}

	private var channelPane: some View {
		pane(ServerPropertiesStrings.Navigation.channelList) {
			List(selection: $model.selectedChannelID) {
				ForEach(model.displayedChannels, id: \.uniqueIdentifier) { channel in
					HStack {
						Toggle(
							ServerPropertiesStrings.ChannelList.joinOnConnect,
							isOn: channelAutoJoinBinding(channel.uniqueIdentifier)
						).labelsHidden()
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
					Button(ServerPropertiesStrings.AddressBookActions.addIgnoreEntry, action: actions.addIgnore)
					Button(ServerPropertiesStrings.AddressBookActions.addTrackingEntry, action: actions.addTracking)
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
			Text(verbatim: ServerPropertiesStrings.ConnectCommands.heading)
				.frame(maxWidth: .infinity, alignment: .leading)
			TextEditor(text: $model.connectCommands).font(.system(.body, design: .monospaced)).frame(minHeight: 280)
			Toggle(
				ServerPropertiesStrings.ConnectCommands.setInvisibleMode,
				isOn: $model.config.setInvisibleModeOnConnect
			)
			Toggle(ServerPropertiesStrings.ConnectCommands.runSilently, isOn: $model.config.runConnectCommandsSilently)
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
		}
	}

	private var messagesPane: some View {
		pane(ServerPropertiesStrings.Navigation.messages) {
			Form {
				TextField(ServerPropertiesStrings.LeavingMessages.normal, text: $model.config.normalLeavingComment)
				TextField(
					ServerPropertiesStrings.LeavingMessages.sleepMode,
					text: $model.config.sleepModeLeavingComment
				)
			}
		}
	}

	private var encodingPane: some View {
		pane(ServerPropertiesStrings.Navigation.encoding) {
			Form {
				Picker(ServerPropertiesStrings.Encoding.primary, selection: $model.config.primaryEncoding) {
					ForEach(encodings, id: \.value) { Text(verbatim: $0.title).tag($0.value) }
				}
				Picker(ServerPropertiesStrings.Encoding.fallback, selection: $model.config.fallbackEncoding) {
					ForEach(encodings, id: \.value) { Text(verbatim: $0.title).tag($0.value) }
				}
			}
		}
	}

	private var zncPane: some View {
		pane(ServerPropertiesStrings.Navigation.zncBouncer) {
			Toggle(
				ServerPropertiesStrings.ZNC.ignoreConfiguredAutojoin,
				isOn: $model.config.zncIgnoreConfiguredAutojoin
			)
			Toggle(
				ServerPropertiesStrings.ZNC.ignorePlaybackNotifications,
				isOn: $model.config.zncIgnorePlaybackNotifications
			)
			Toggle(ServerPropertiesStrings.ZNC.onlyPlaybackLatest, isOn: $model.config.zncOnlyPlaybackLatest)
			Text(verbatim: ServerPropertiesStrings.ZNC.versionNote).foregroundStyle(.secondary)
		}
	}

	private var certificatePane: some View {
		pane(ServerPropertiesStrings.Navigation.clientCertificate) {
			Form {
				LabeledContent(ServerPropertiesStrings.Certificate.name, value: model.certificateName)
				fingerprint(ServerPropertiesStrings.Certificate.fingerprintSHA512, model.certificateSHA512)
				fingerprint(ServerPropertiesStrings.Certificate.fingerprintSHA256, model.certificateSHA256)
				fingerprint(ServerPropertiesStrings.Certificate.fingerprintSHA1, model.certificateSHA1)
			}
			HStack {
				Button(ServerPropertiesStrings.Certificate.select, action: actions.chooseCertificate)
				Button(ServerPropertiesStrings.Certificate.reset, action: actions.resetCertificate)
					.disabled(model.config.identityClientSideCertificate == nil)
			}
		}
	}

	private var socketPane: some View {
		pane(ServerPropertiesStrings.Navigation.networkSocket) {
			Picker(ServerPropertiesStrings.Socket.connectUsing, selection: $model.config.addressType) {
				ForEach(Self.addressTypes, id: \.self) { addressType in
					Text(verbatim: ServerPropertiesStrings.Socket.addressType(addressType)).tag(addressType)
				}
			}.pickerStyle(.radioGroup)
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
			Picker(ServerPropertiesStrings.CipherSuites.label, selection: $model.config.cipherSuites) {
				ForEach(Self.cipherSuiteCollections, id: \.self) { collection in
					Text(verbatim: ServerPropertiesStrings.CipherSuites.collectionName(collection)).tag(collection)
				}
			}
			Button(ServerPropertiesStrings.CipherSuites.viewList, action: actions.showCipherSuites)
				.disabled(model.config.cipherSuites == .none)
		}
	}

	private var proxyPane: some View {
		pane(ServerPropertiesStrings.Navigation.proxyServer) {
			Picker(ServerPropertiesStrings.Proxy.type, selection: $model.config.proxyType) {
				ForEach(Self.proxyTypes, id: \.self) { proxyType in
					Text(verbatim: ServerPropertiesStrings.Proxy.typeName(proxyType)).tag(proxyType)
				}
			}
			if ServerPropertiesModel.proxyTypeUsesAddress(model.config.proxyType) {
				Form {
					TextField(ServerPropertiesStrings.Proxy.address, text: $model.proxyAddress)
					TextField(ServerPropertiesStrings.Proxy.port, text: $model.proxyPort)
					if model.config.proxyType == .socks5 {
						TextField(ServerPropertiesStrings.Proxy.username, text: $model.proxyUsername)
						SecureField(ServerPropertiesStrings.Proxy.password, text: $model.proxyPassword)
					}
				}
			} else if model.config.proxyType == .automatic {
				Button(ServerPropertiesStrings.Proxy.openSystemSettings) {
					if let url = Self.networkProxySettingsURL {
						openURL(url)
					}
				}
			} else if model.config.proxyType == .tor {
				Text(verbatim: ServerPropertiesStrings.Proxy.torBrowserNote).foregroundStyle(.secondary)
			}
		}
	}

	private var floodPane: some View {
		pane(ServerPropertiesStrings.Navigation.floodControl) {
			LabeledContent(
				ServerPropertiesStrings.FloodControl.messageCount,
				value: String(model.config.floodControlMaximumMessages)
			)
			Slider(value: uintBinding(\.floodControlMaximumMessages), in: 1 ... 60, step: 1)
			LabeledContent(
				ServerPropertiesStrings.FloodControl.interval,
				value: String(model.config.floodControlDelayTimerInterval)
			)
			Slider(value: uintBinding(\.floodControlDelayTimerInterval), in: 1 ... 60, step: 1)
		}
	}

	private var redundancyPane: some View {
		pane(ServerPropertiesStrings.Navigation.redundancy) {
			Toggle(ServerPropertiesStrings.General.reconnectAfterDisconnect, isOn: $model.config.autoReconnect)
			Toggle(
				ServerPropertiesStrings.General.disconnectWhenComputerSleeps,
				isOn: $model.config.autoSleepModeDisconnect
			)
			Toggle(
				ServerPropertiesStrings.Socket.disconnectOnReachabilityChange,
				isOn: $model.config.performDisconnectOnReachabilityChange
			)
			Button(ServerPropertiesStrings.General.modifyAlternateServers, action: actions.editEndpoints)
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
			Button(ServerPropertiesStrings.Certificate.copyFingerprint) { actions.copyCertificateFingerprint(value) }
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
