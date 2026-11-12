// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

struct ServerPropertiesView: View {
	@Bindable var model: ServerPropertiesModel

	/** What the view asks its editor to do.

	 Weak because the editor outlives nothing it draws: a view still on screen
	 after its editor has gone has nothing left to ask, which is what `nil`
	 means. */
	weak var commands: (any ServerPropertiesCommands)?

	var body: some View {
		Group {
			if let picker = model.templatePicker {
				ServerTemplatePickerView(model: model, picker: picker, commands: commands)
			} else {
				form
			}
		}
		.disabled(model.isSaving)
		/* The window's keychain secrets are read once as it opens, and the
		 certificate's description again whenever a different one is chosen. */
		.task { await model.loadSecrets() }
		.task(id: model.config.identityClientSideCertificate) { await model.loadCertificate() }
	}

	private var form: some View {
		NavigationSplitView {
			List(selection: $model.selection) {
				if model.isBouncerNetwork {
					/* A network of a bouncer account takes its identity, endpoint and
					 socket settings from the account. */
					Section(.ServerProperties.navigationSectionConnection) {
						navigationRows([.channelList, .highlights, .connectCommands])
						if model.profile != nil {
							navigationRows([.profile])
						}
					}
					Section(.ServerProperties.bouncer) {
						navigationRows([.bouncerNetworks])
					}
				} else {
					Section(.ServerProperties.navigationSectionConnection) {
						navigationRows([.general, .identity])
						if model.profile != nil {
							navigationRows([.profile])
						}
						navigationRows([
							.channelList, .highlights,
							.connectCommands, .disconnectMessages, .encoding,
						])
					}
					Section(.ServerProperties.bouncer) {
						navigationRows([.zncBouncer, .bouncerNetworks])
					}
					Section(.ServerProperties.serverPropertiesNavigationMenuAdvanced) {
						navigationRows([.clientCertificate, .networkSocket, .proxyServer, .floodControl])
					}
				}
			}
			.listStyle(.sidebar)
			.navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
			/* The pane list is always shown, as it is in System Settings, so the
			 toggle a split view adds would be a button that hides the window's
			 only way between panes. */
			.toolbar(removing: .sidebarToggle)
		} detail: {
			VStack(spacing: 0) {
				selectedPane
					.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
				actions
			}
		}
	}

	/** Save and Revert, under the pane.

	 The window is not modal, so neither button has the keys a sheet's do:
	 Escape must not throw edits away and Return must not save while a field is
	 being typed in. Save is Command-S, as it is for a document. A new
	 connection has nothing to revert to, so its window offers Cancel. */
	private var actions: some View {
		HStack(spacing: UISpacing.regular) {
			if let message = model.validationMessage {
				ValidationMessageLabel(message)
			}
			Spacer(minLength: UISpacing.loose)
			if model.isNewServer {
				Button(PromptStrings.Action.cancel) { commands?.cancel() }
					.accessibilityIdentifier(AccessibilityIdentifier.serverPropertiesRevert)
			} else {
				Button(.ServerProperties.revertButton) { commands?.cancel() }
					.disabled(model.hasUnsavedChanges == false)
					.help(Text(.ServerProperties.revertHelp))
					.accessibilityIdentifier(AccessibilityIdentifier.serverPropertiesRevert)
			}
			Button(PromptStrings.Action.save) { commands?.submit() }
				.keyboardShortcut("s", modifiers: .command)
				.buttonStyle(.borderedProminent)
				.disabled(model.validationMessage != nil)
				.accessibilityIdentifier(AccessibilityIdentifier.serverPropertiesSave)
		}
		.padding(.top, UISpacing.wide)
		.padding([.horizontal, .bottom], SheetMetrics.margin)
	}

	@ViewBuilder
	private var selectedPane: some View {
		switch model.selection {
		case .general: ServerPropertiesGeneralPane(model: model, commands: commands)
		case .identity: ServerPropertiesIdentityPane(model: model)
		case .profile:
			if let profile = model.profile {
				ServerPropertiesProfilePane(profile: profile)
			}
		case .channelList: ServerPropertiesChannelListPane(model: model, commands: commands)
		case .highlights: ServerPropertiesHighlightsPane(model: model, commands: commands)
		case .connectCommands: ServerPropertiesConnectCommandsPane(model: model)
		case .disconnectMessages: ServerPropertiesDisconnectMessagesPane(model: model)
		case .encoding: ServerPropertiesEncodingPane(model: model)
		case .zncBouncer: ServerPropertiesZNCBouncerPane(model: model)
		case .bouncerNetworks: ServerPropertiesBouncerPane(model: model)
		case .clientCertificate: ServerPropertiesClientCertificatePane(model: model, commands: commands)
		case .networkSocket: ServerPropertiesNetworkSocketPane(model: model)
		case .proxyServer: ServerPropertiesProxyServerPane(model: model)
		case .floodControl: ServerPropertiesFloodControlPane(model: model)
		}
	}

	/// The sidebar lists the panes in its own order, which is the order they are
	/// written here; each row's title and symbol belong to the pane itself.
	private func navigationRows(_ panes: [ServerPropertiesSelection]) -> some View {
		ForEach(panes, id: \.self) { pane in
			Label(pane.title, systemImage: pane.symbol).tag(pane)
				.accessibilityIdentifier(AccessibilityIdentifier.serverPropertiesPane(String(describing: pane)))
		}
	}
}
