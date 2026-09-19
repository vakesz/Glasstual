// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import SwiftUI

/* The vendor and advanced panes of the connection sheet: the bouncer, the session
 certificate, the socket, the proxy and flood control. */

struct ServerPropertiesZNCBouncerPane: View {
	@Bindable var model: ServerPropertiesModel

	var body: some View {
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

struct ServerPropertiesClientCertificatePane: View {
	let model: ServerPropertiesModel
	/// Weak for the same reason `ServerPropertiesView`'s is: the sheet holds the
	/// view that holds this pane.
	weak var commands: (any ServerPropertiesCommands)?

	var body: some View {
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
					Button(.ServerProperties.selectCertificate) { commands?.chooseCertificate() }
					Button(.ServerProperties.resetCertificate, role: .destructive) {
						commands?.resetCertificate()
					}
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

	private func fingerprint(_ label: LocalizedStringResource, _ value: String) -> some View {
		LabeledContent(label) {
			HStack {
				Text(verbatim: value)
					.font(.system(.caption, design: .monospaced))
					.textSelection(.enabled)
					.lineLimit(1)
					.truncationMode(.middle)
				Button(.ServerProperties.copyNickservCommand) {
					commands?.copyNickServCommand(for: value)
				}
				.help(.ServerProperties.copyNickservCommandFor(String(localized: label)))
				.accessibilityLabel(.ServerProperties.copyNickservCommandFor(String(localized: label)))
			}
		}
	}
}

struct ServerPropertiesNetworkSocketPane: View {
	@Bindable var model: ServerPropertiesModel

	/* The pickers list their options in a deliberate order rather than the
	 declaration order of the enums, so each carries its own array. */
	private static let addressTypes: [ConnectionAddressKind] = [.default, .v4, .v6]
	private static let cipherSuiteCollections: [CipherSuiteCollection] = [
		.system, .modern, .intermediate,
	]

	var body: some View {
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
				if model.config.cipherSuites != .system {
					cipherSuiteList
				}
			} footer: {
				if model.config.cipherSuites != .system {
					Text(.ServerProperties.includesTheFollowingCipherSuites(
						String(localized: model.config.cipherSuites.title)
					))
				}
			}
		}
		.formStyle(.grouped)
	}

	/// The suites of the chosen collection, in the pane rather than in an alert
	/// whose body was a hundred lines of proportional text.
	private var cipherSuiteList: some View {
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
			.padding(.top, UISpacing.tight)
		}
	}
}

struct ServerPropertiesProxyServerPane: View {
	@Bindable var model: ServerPropertiesModel
	@Environment(\.openURL) private var openURL

	private static let proxyTypes: [ConnectionProxyKind] = [.none, .automatic, .socks5, .HTTP, .tor]

	private static let networkProxySettingsURL = URL(
		string: "x-apple.systempreferences:com.apple.Network-Settings.extension?Proxies"
	)

	var body: some View {
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

struct ServerPropertiesFloodControlPane: View {
	@Bindable var model: ServerPropertiesModel

	var body: some View {
		Form {
			Section {
				slider(
					.ServerProperties.floodControlMessageCount,
					value: binding(\.floodControlMaximumMessages),
					current: Int(model.config.floodControlMaximumMessages)
				)
				slider(
					.ServerProperties.floodControlInterval,
					value: binding(\.floodControlDelayTimerInterval),
					current: Int(model.config.floodControlDelayTimerInterval)
				)
			}
		}
		.formStyle(.grouped)
	}

	private func slider(
		_ label: LocalizedStringResource,
		value: Binding<Double>,
		current: Int
	) -> some View {
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

	/// A `Slider` works in `Double`; both limits are stored as counts.
	private func binding(_ keyPath: WritableKeyPath<ServerConfig, UInt>) -> Binding<Double> {
		Binding(get: { Double(model.config[keyPath: keyPath]) },
		        set: { model.config[keyPath: keyPath] = UInt($0) })
	}
}

// MARK: - Picker copy

/** The copy the connection sheet names its closed choices with.

 Each of these is a set the sheet draws a picker from, so the name belongs to
 the case rather than to whichever row happens to show it. */
extension ConnectionAddressKind {
	var title: LocalizedStringResource {
		switch self {
		case .default: .ServerProperties.addressTypeAutomatic
		case .v4: .ServerProperties.addressTypeIpv4
		case .v6: .ServerProperties.addressTypeIpv6
		}
	}
}

extension ConnectionProxyKind {
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
		case .system: .ServerProperties.cipherSuitesSystem
		case .modern: .ServerProperties.cipherSuitesModern
		case .intermediate: .ServerProperties.cipherSuitesIntermediate
		}
	}
}
