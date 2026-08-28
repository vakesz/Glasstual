/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import SwiftUI

/** The window's whole content: the pane list on the left, the selected pane on
 the right.

 The shell owns the window, the toolbar and which pane is selected; this view
 only reports a new selection back through the binding. */
struct PreferencesRootView: View {
	@Bindable var model: PreferencesPaneModel

	private var mainEntries: [PreferencesSidebarEntry] {
		model.entries.filter { $0.group == .main }
	}

	private var addOnEntries: [PreferencesSidebarEntry] {
		model.entries.filter { $0.group == .addOns }
	}

	private var advancedEntries: [PreferencesSidebarEntry] {
		model.entries.filter { $0.group == .advanced }
	}

	var body: some View {
		NavigationSplitView {
			sidebar
		} detail: {
			PreferencesPaneRouter(model: model, identifier: model.selectedPaneIdentifier)
				.frame(minWidth: PreferencesLayout.detailMinimumWidth)
		}
		.navigationSplitViewStyle(.balanced)
	}

	private var sidebar: some View {
		List(selection: $model.selectedPaneIdentifier) {
			ForEach(mainEntries, id: \.identifier) { entry in
				row(entry)
			}
			if addOnEntries.isEmpty == false {
				Section {
					ForEach(addOnEntries, id: \.identifier) { entry in
						row(entry)
					}
				} header: {
					Text(verbatim: PreferencesStrings.addOnsGroupTitle)
				}
			}
			if advancedEntries.isEmpty == false {
				Section {
					ForEach(advancedEntries, id: \.identifier) { entry in
						row(entry)
					}
				} header: {
					Text(verbatim: PreferencesStrings.advancedGroupTitle)
				}
			}
		}
		.navigationSplitViewColumnWidth(
			min: PreferencesLayout.sidebarMinimumWidth,
			ideal: PreferencesLayout.sidebarPreferredWidth,
			max: PreferencesLayout.sidebarMaximumWidth
		)
		.accessibilityLabel(Text(verbatim: PreferencesStrings.accessibilityTitle))
		.safeAreaInset(edge: .bottom) {
			Text(verbatim: model.versionFooter)
				.font(.footnote)
				.foregroundStyle(.tertiary)
				.lineLimit(1)
				.padding(.horizontal, 18)
				.padding(.bottom, 10)
				.frame(maxWidth: .infinity, alignment: .leading)
		}
	}

	private func row(_ entry: PreferencesSidebarEntry) -> some View {
		Label {
			Text(verbatim: entry.title)
		} icon: {
			Image(systemName: entry.symbolName)
		}
		.accessibilityLabel(Text(verbatim: entry.title))
	}
}

/// Maps a sidebar identifier onto the pane that answers to it.
struct PreferencesPaneRouter: View {
	/// A plugin's own preference view, which is AppKit and stays that way.
	private static let pluginPaneHeight = 420.0

	let model: PreferencesPaneModel
	let identifier: String?

	var body: some View {
		if let index = identifier.flatMap(PreferencesPaneCatalog.pluginIndex(from:)) {
			pluginPane(at: index)
		} else if let pane = identifier.flatMap(PreferencesPaneIdentifier.init(rawValue:)) {
			view(for: pane)
		} else {
			PreferencesGeneralPane(model: model)
		}
	}

	@ViewBuilder
	private func view(for pane: PreferencesPaneIdentifier) -> some View {
		switch pane {
		case .addOns: PreferencesAddOnsPane(model: model)
		case .behavior: PreferencesBehaviorPane(model: model)
		case .channelManagement: PreferencesChannelManagementPane(model: model)
		case .commandScope: PreferencesCommandScopePane(model: model)
		case .compatibility: PreferencesCompatibilityPane(model: model)
		case .controls: PreferencesControlsPane(model: model)
		case .defaultIRCopMessages: PreferencesIRCopMessagesPane(model: model)
		case .defaultIdentity: PreferencesDefaultIdentityPane(model: model)
		case .fileTransfers: PreferencesFileTransfersPane(model: model)
		case .floodControl: PreferencesFloodControlPane(model: model)
		case .general: PreferencesGeneralPane(model: model)
		case .hidden: PreferencesHiddenPane(model: model)
		case .highlights: PreferencesHighlightsPane(model: model)
		case .incomingData: PreferencesIncomingDataPane(model: model)
		case .inlineMedia: PreferencesInlineMediaPane(model: model)
		case .interface: PreferencesInterfacePane(model: model)
		case .logLocation: PreferencesLogLocationPane(model: model)
		case .notifications: PreferencesNotificationsPane(model: model)
		case .style: PreferencesStylePane(model: model)
		}
	}

	@ViewBuilder
	private func pluginPane(at index: Int) -> some View {
		let plugins = SharedApplication.sharedPluginManager().pluginsWithPreferencePanes
		if plugins.indices.contains(index), let view = plugins[index].pluginPreferencesPaneView {
			ScrollView {
				PreferencesHostedView(view: view, height: Self.pluginPaneHeight)
					.padding(20)
			}
		}
	}
}
