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

/** The window's content below the toolbar: the selected section's pane, with a
 segmented picker above it when the section holds more than one.

 The AppKit shell owns the toolbar and therefore the section; this view only
 reports a change of sub-page back through the model. */
struct PreferencesRootView: View {
	@Bindable var model: PreferencesPaneModel

	private var subPages: [PreferencesSubPage] {
		model.currentSection?.subPages ?? []
	}

	private var currentSubPage: PreferencesSubPage? {
		subPages.first { $0.identifier == model.selectedPane }
	}

	var body: some View {
		ScrollView {
			VStack(spacing: 0) {
				if subPages.count > 1 {
					subPagePicker
				}
				if let currentSubPage {
					PreferencesSubPageView(model: model, subPage: currentSubPage)
				}
			}
		}
		.frame(width: PreferencesLayout.windowWidth)
	}

	/** The picker keeps to the form's own width so no section can push the
	 window wider; a section with more sub-pages than a segmented row holds
	 lists them in a pop-up instead. */
	private var subPagePicker: some View {
		pickerContent
			.frame(maxWidth: .infinity)
			.padding(.horizontal, PreferencesLayout.contentInset)
			.padding(.top, 14)
	}

	/** A segmented row while the section's labels fit across the window, and a
	 pop-up when they would not: a segment is never allowed to truncate, and the
	 row never widens the window. */
	@ViewBuilder
	private var pickerContent: some View {
		if model.currentSection?.usesSegmentedPicker ?? true {
			picker.pickerStyle(.segmented).fixedSize()
		} else {
			picker.pickerStyle(.menu).fixedSize()
		}
	}

	private var picker: some View {
		Picker(selection: $model.selectedPane) {
			ForEach(subPages) { subPage in
				Text(verbatim: subPage.title).tag(subPage.identifier)
			}
		} label: {
			EmptyView()
		}
		.labelsHidden()
		.accessibilityLabel(Text(verbatim: model.currentSection?.title ?? ""))
	}
}

/** One segment's content: the pane on its own, or the several panes an Advanced
 group gathers, drawn as one form whose sections carry the old pane names. */
struct PreferencesSubPageView: View {
	let model: PreferencesPaneModel
	let subPage: PreferencesSubPage

	var body: some View {
		if subPage.panes.count == 1, let pane = subPage.panes.first {
			PreferencesPaneRouter(model: model, identifier: pane.identifier)
		} else {
			PreferencesPaneLayout {
				ForEach(subPage.panes) { pane in
					PreferencesGroupedPaneSections(model: model, identifier: pane.identifier)
				}
			}
		}
	}
}

/// The sections of one advanced pane, for the group that gathers it.
struct PreferencesGroupedPaneSections: View {
	let model: PreferencesPaneModel
	let identifier: String

	var body: some View {
		switch PreferencesPaneIdentifier(rawValue: identifier) {
		case .channelManagement: PreferencesChannelManagementSections(model: model)
		case .commandScope: PreferencesCommandScopeSections(model: model)
		case .compatibility: PreferencesCompatibilitySections(model: model)
		case .defaultIRCopMessages: PreferencesIRCopMessagesSections(model: model)
		case .defaultIdentity: PreferencesDefaultIdentitySections(model: model)
		case .fileTransfers: PreferencesFileTransfersSections(model: model)
		case .floodControl: PreferencesFloodControlSections(model: model)
		case .hidden: PreferencesHiddenSections(model: model)
		case .incomingData: PreferencesIncomingDataSections(model: model)
		case .inlineMedia: PreferencesInlineMediaSections(model: model)
		case .logLocation: PreferencesLogLocationSections(model: model)
		default: EmptyView()
		}
	}
}

/// Maps a pane identifier onto the view that answers to it.
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
			PreferencesHostedView(view: view, height: Self.pluginPaneHeight)
				.padding(20)
		}
	}
}
