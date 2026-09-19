// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import SwiftUI

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
				Button(.ServerProperties.modifyAlternateServers) { commands?.editEndpoints() }
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

struct ServerPropertiesIdentityPane: View {
	@Bindable var model: ServerPropertiesModel

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
	private static let encodings: [(value: UInt, title: String)] = {
		let values = String.Encoding.supportedEncodingsByTitle(favoringUTF8: false)
		return values.map { ($0.value.uintValue, $0.key) }.sorted { $0.title < $1.title }
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
