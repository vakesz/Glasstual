// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import SwiftUI
import UniformTypeIdentifiers

/* The panes of the connection sheet's first section: what the connection is,
 who it logs in as, and what it says on the way in and out. Each one is a view
 of its own rather than a computed property of the sheet's content, so editing a
 field redraws the pane it is on and nothing else. */

struct ServerPropertiesGeneralPane: View {
	@Bindable var model: ServerPropertiesModel
	/// Weak for the same reason `ServerPropertiesView`'s is: the sheet holds the
	/// view that holds this pane.
	weak var commands: (any ServerPropertiesCommands)?

	var body: some View {
		Form {
			Section {
				TextField(.ServerProperties.connectionName, text: $model.config.connectionName)
				Picker(.ServerProperties.connectionType, selection: $model.primaryServerTransport) {
					Text(.ServerProperties.transportIrc).tag(ServerTransport.irc)
					Text(.ServerProperties.transportWebSocket).tag(ServerTransport.webSocket)
				}
				.pickerStyle(.segmented)
				.accessibilityIdentifier("server-connection-type")
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
				if model.primaryServerTransport == .webSocket {
					TextField(.ServerProperties.webSocketPath, text: $model.primaryWebSocketPath, prompt: Text(verbatim: "/"))
						.help(.ServerProperties.webSocketPathHelp)
						.accessibilityIdentifier("server-websocket-path")
				}
				Toggle(.ServerProperties.connectSecurely, isOn: $model.primaryServerIsSecured)
				SecureField(.ServerProperties.serverPassword, text: model.secretBinding(.serverPassword))
			} footer: {
				VStack(alignment: .leading) {
					Text(.ServerProperties.serverPasswordHelp)
					if model.primaryServerTransport == .webSocket {
						Text(.ServerProperties.connectSecurelyWebSocketFooter)
					}
				}
			}

			Section {
				Button(.ServerProperties.modifyAlternateServers) { commands?.editEndpoints() }
			}

			ServerIdentityPicker(style: $model.config.sidebarIdentity, name: model.config.connectionName)

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

struct ServerPropertiesIdentityPane: View {
	@Bindable var model: ServerPropertiesModel
	@State private var isImportingSigningKey = false
	@State private var isConfirmingSigningKeyDeletion = false

	var body: some View {
		Form {
			Section {
				TextField(.ServerProperties.nickname, text: $model.config.nickname)
				TextField(
					.ServerProperties.awayNickname,
					text: $model.config.awayNickname.orEmpty
				)
				TextField(
					.ServerProperties.alternativeNicknames,
					text: $model.alternateNicknames
				)
				TextField(.ServerProperties.username, text: $model.config.username)
				TextField(.ServerProperties.realName, text: $model.config.realName)
				TextField(
					.ServerProperties.ctcpVersionReply,
					text: $model.config.ctcpVersionReply.orEmpty
				)
			}

			ServerPropertiesAuthenticationSection(model: model)

			Section {
				if model.hasSigningKey {
					Text(.ServerProperties.saslEcdsaKeyStored)
						.foregroundStyle(.secondary)
				} else {
					Text(.ServerProperties.saslEcdsaKeyMissing)
						.foregroundStyle(.secondary)
				}
				if let publicKey = model.signingPublicKey {
					LabeledContent(.ServerProperties.saslEcdsaPublicKeyLabel) {
						Text(verbatim: publicKey)
							.font(.callout.monospaced())
							.textSelection(.enabled)
					}
				}
				HStack {
					Button(.ServerProperties.saslEcdsaGenerateKeyButton) { model.generateSigningKey() }
					Button(.ServerProperties.saslEcdsaImportKeyButton) { isImportingSigningKey = true }
					Button(.ServerProperties.saslEcdsaCopyPublicKeyButton) {
						NSPasteboard.general.stringContent = model.signingPublicKey
					}
					.disabled(model.hasSigningKey == false)
					Button(.ServerProperties.saslEcdsaDeleteKeyButton, role: .destructive) {
						isConfirmingSigningKeyDeletion = true
					}
					.disabled(model.hasSigningKey == false)
				}
				if let error = model.signingKeyError {
					ValidationMessageLabel(error)
				}
			} header: {
				Text(.ServerProperties.saslEcdsaKeyHeader)
			} footer: {
				Text(.ServerProperties.saslEcdsaKeyHelp)
			}
			.fileImporter(isPresented: $isImportingSigningKey, allowedContentTypes: [.data]) { result in
				model.importSigningKey(fromFile: result)
			}
			.alert(
				String(localized: .ServerProperties.saslEcdsaDeleteKeyTitle),
				isPresented: $isConfirmingSigningKeyDeletion
			) {
				Button(String(localized: .ServerProperties.saslEcdsaDeleteKeyConfirmButton), role: .destructive) {
					model.removeSigningKey()
				}
				Button(PromptStrings.Action.cancel, role: .cancel) {}
			} message: {
				Text(.ServerProperties.saslEcdsaDeleteKeyMessage)
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

	/// The stored setting hides the warnings; the toggle offers them, so it reads
	/// as the thing the person wants rather than as the thing they are refusing.
	private var warningBinding: Binding<Bool> {
		Binding(get: { model.config.hideAutojoinDelayedWarnings == false },
		        set: { model.config.hideAutojoinDelayedWarnings = $0 == false })
	}
}

struct ServerPropertiesConnectCommandsPane: View {
	@Bindable var model: ServerPropertiesModel

	var body: some View {
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
					in: 0 ... ServerConfigDefaults.maximumAutojoinConnectCommandDelay,
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

struct ServerPropertiesDisconnectMessagesPane: View {
	@Bindable var model: ServerPropertiesModel

	var body: some View {
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

struct ServerPropertiesEncodingPane: View {
	@Bindable var model: ServerPropertiesModel

	/// Built once for the process: the list is the same for every sheet, and
	/// sorting several hundred encoding names is not work to repeat per view.
	/// Only encodings that keep ASCII as ASCII can carry IRC lines.
	private static let encodings: [(value: UInt, title: String)] = {
		let values = String.Encoding.supportedEncodingsByTitle(favoringUTF8: false)
		return values
			.map { ($0.value.uintValue, $0.key) }
			.filter { TextEncodingOptions.isWireCompatible(String.Encoding(rawValue: $0.0)) }
			.sorted { $0.title < $1.title }
	}()

	var body: some View {
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
