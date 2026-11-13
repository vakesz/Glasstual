// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/// The Identity pane's Authentication section: the account password, whether
/// and how SASL signs in, and what happens when it cannot.
struct ServerPropertiesAuthenticationSection: View {
	@Bindable var model: ServerPropertiesModel

	var body: some View {
		Section {
			SecureField(
				.ServerProperties.nickservOrSaslPassword,
				text: model.secretBinding(.nicknamePassword)
			)
			.accessibilityIdentifier(AccessibilityIdentifier.serverPropertiesNicknamePassword)
			/* The onboarding network picker was the only place this
			 could be chosen, so a connection made any other way was
			 stuck with the default until someone hand-edited the
			 stored configuration. */
			Toggle(.ServerProperties.signInWithSasl, isOn: $model.config.usesSASL)
				.accessibilityIdentifier(AccessibilityIdentifier.serverPropertiesSASLEnabled)
			Picker(.ServerProperties.saslMechanism, selection: $model.saslMechanismChoice) {
				Text(.ServerProperties.saslMechanismAutomatic)
					.tag(SASLMechanismChoice.automatic)
					.accessibilityIdentifier(AccessibilityIdentifier.serverPropertiesSASLMechanism("automatic"))
				Divider()
				ForEach(SASLMechanism.defaultOrder, id: \.self) { mechanism in
					Text(verbatim: "\(mechanism.localizedTitle) — \(mechanism.wireName)")
						.tag(SASLMechanismChoice.mechanism(mechanism))
						.accessibilityIdentifier(AccessibilityIdentifier.serverPropertiesSASLMechanism(mechanism.wireName))
				}
			}
			.pickerStyle(.menu)
			.disabled(model.config.usesSASL == false)
			.accessibilityIdentifier(AccessibilityIdentifier.serverPropertiesSASLMechanism)
			Toggle(
				.ServerProperties.saslMechanismOnly,
				isOn: $model.config.saslUsesOnlyPreferredMechanism
			)
			.disabled(model.config.usesSASL == false || model.config.saslMechanismPreference == nil)
			.accessibilityIdentifier(AccessibilityIdentifier.serverPropertiesSASLMechanismOnly)
			SecureField(
				.ServerProperties.saslBearerToken,
				text: model.secretBinding(.saslBearerToken)
			)
			.accessibilityIdentifier("server-sasl-bearer-token")
			.accessibilityHint(.ServerProperties.saslBearerTokenHelp)
			Toggle(
				.ServerProperties.saslReauthenticatesAutomatically,
				isOn: $model.config.saslReauthenticatesAutomatically
			)
			.disabled(model.config.usesSASL == false)
			.accessibilityIdentifier("server-sasl-reauthenticates")
			Toggle(
				.ServerProperties.disconnectOnSaslFailure,
				isOn: $model.config.disconnectOnSASLFailure
			)
			Toggle(
				.ServerProperties.autojoinWaitsForNickserv,
				isOn: $model.config.autojoinWaitsForNickServ
			)
		} header: {
			Text(.ServerProperties.authenticationHeader)
		} footer: {
			VStack(alignment: .leading, spacing: 6) {
				if let warning = model.saslMechanismWarning {
					Label {
						Text(verbatim: warning)
							.foregroundStyle(.primary)
					} icon: {
						Image(systemName: "exclamationmark.triangle.fill")
							.foregroundStyle(.yellow)
					}
					.font(.callout)
					.accessibilityElement(children: .ignore)
					.accessibilityLabel(Text(verbatim: warning))
				}
				Text(.ServerProperties.nicknamePasswordHelp)
				Text(.ServerProperties.saslBearerTokenHelp)
			}
		}
	}
}
