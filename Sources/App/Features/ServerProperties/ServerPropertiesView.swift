// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

struct ServerPropertiesView: View {
	@Bindable var model: ServerPropertiesModel

	/** What the view asks its sheet to do.

	 Weak because the sheet holds this view as its content: a strong reference
	 here would keep the sheet alive through itself. A view still on screen
	 after its sheet has gone has nothing left to ask, which is what `nil`
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
						navigationRows([
							.general, .identity, .channelList, .highlights, .addressBook,
							.connectCommands, .disconnectMessages, .encoding,
						])
					}
					Section(.ServerProperties.vendorSpecific) {
						navigationRows([.zncBouncer])
					}
					Section(.ServerProperties.serverPropertiesNavigationMenuAdvanced) {
						navigationRows([.clientCertificate, .networkSocket, .proxyServer, .floodControl])
					}
				}
				.listStyle(.sidebar)
				.navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
			} detail: {
				pane
			}
			/* A sheet has no toolbar to put a sidebar toggle in, so the one the
			 split view adds by default lands on top of the section list. The
			 list is always visible here anyway. */
			.toolbar(removing: .sidebarToggle)

			SheetActions(
				confirmTitle: Text(PromptStrings.Action.save),
				confirmIsDisabled: model.validationMessage != nil,
				confirm: { commands?.submit() },
				cancel: { commands?.cancel() },
				leading: {
					if let message = model.validationMessage {
						ValidationMessageLabel(message)
					}
				}
			)
		}
	}

	/// The selected pane under its own heading: the heading is drawn here, once,
	/// from the selection that named the pane.
	private var pane: some View {
		VStack(alignment: .leading, spacing: UISpacing.wide) {
			Text(model.selection.title)
				.font(.title2)
				.fontWeight(.semibold)
				.padding([.horizontal, .top], SheetMetrics.margin)

			selectedPane
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
	}

	@ViewBuilder
	private var selectedPane: some View {
		switch model.selection {
		case .general: ServerPropertiesGeneralPane(model: model, commands: commands)
		case .identity: ServerPropertiesIdentityPane(model: model)
		case .channelList: ServerPropertiesChannelListPane(model: model, commands: commands)
		case .highlights: ServerPropertiesHighlightsPane(model: model, commands: commands)
		case .addressBook: ServerPropertiesAddressBookPane(model: model, commands: commands)
		case .connectCommands: ServerPropertiesConnectCommandsPane(model: model)
		case .disconnectMessages: ServerPropertiesDisconnectMessagesPane(model: model)
		case .encoding: ServerPropertiesEncodingPane(model: model)
		case .zncBouncer: ServerPropertiesZNCBouncerPane(model: model)
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
		}
	}
}
