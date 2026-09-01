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

/// The complete Settings interface. SwiftUI owns sidebar selection, detail
/// routing, navigation history, toolbar commands, and pane layout; the AppKit
/// shell exists only to configure the macOS window.
struct PreferencesRootView: View {
	@Bindable var model: PreferencesPaneModel
	@State private var history = [PreferencesSelection.general]
	@State private var historyIndex = 0

	private var sectionSelection: Binding<PreferencesSectionIdentifier?> {
		Binding(
			get: { model.selection.sectionIdentifier },
			set: { identifier in
				guard let identifier else { return }
				model.selectSection(identifier)
			}
		)
	}

	private var subPages: [PreferencesSubPage] {
		model.currentSection?.subPages ?? []
	}

	private var currentSubPage: PreferencesSubPage? {
		subPages.first { $0.identifier == model.selection.subPageIdentifier }
	}

	private var selectedSubPage: Binding<String> {
		Binding(
			get: { model.selection.subPageIdentifier },
			set: { _ = model.selectSubPage($0) }
		)
	}

	var body: some View {
		NavigationSplitView(columnVisibility: .constant(.all)) {
			List(selection: sectionSelection) {
				ForEach(model.sections) { section in
					Label(section.title, systemImage: section.symbolName)
						.tag(section.identifier)
				}
			}
			.listStyle(.sidebar)
			.scrollEdgeEffectStyle(.soft, for: .all)
			.navigationTitle(PreferencesStrings.accessibilityTitle)
			.navigationSplitViewColumnWidth(
				min: PreferencesLayout.sidebarWidth,
				ideal: PreferencesLayout.sidebarWidth,
				max: PreferencesLayout.sidebarWidth + 40
			)
		} detail: {
			detail
		}
		.navigationSplitViewStyle(.balanced)
		.frame(
			minWidth: PreferencesLayout.minimumWindowSize.width,
			minHeight: PreferencesLayout.minimumWindowSize.height
		)
		.toolbar {
			ToolbarItemGroup(placement: .navigation) {
				Button(PreferencesNavigationStrings.back, systemImage: "chevron.left", action: goBack)
					.disabled(historyIndex == 0)
				Button(PreferencesNavigationStrings.forward, systemImage: "chevron.right", action: goForward)
					.disabled(historyIndex >= history.count - 1)
			}
		}
		.onChange(of: model.selection) { _, selection in
			record(selection)
		}
	}

	private var detail: some View {
		VStack(spacing: 0) {
			if subPages.count > 1 {
				subPagePicker
			}
			if let currentSubPage {
				PreferencesSubPageView(model: model, subPage: currentSubPage)
			} else {
				ContentUnavailableView(
					PreferencesStrings.accessibilityTitle,
					systemImage: "gearshape"
				)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		.navigationTitle(model.currentSection?.title ?? PreferencesStrings.accessibilityTitle)
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

	/// Uses segments when they fit and automatically falls back to a menu.
	private var pickerContent: some View {
		ViewThatFits(in: .horizontal) {
			picker
				.pickerStyle(.segmented)
				.fixedSize()
			picker
				.pickerStyle(.menu)
				.fixedSize()
		}
	}

	private var picker: some View {
		Picker(selection: selectedSubPage) {
			ForEach(subPages) { subPage in
				Text(verbatim: subPage.title).tag(subPage.identifier)
			}
		} label: {
			EmptyView()
		}
		.labelsHidden()
		.accessibilityLabel(Text(verbatim: model.currentSection?.title ?? ""))
	}

	private func goBack() {
		guard historyIndex > 0 else { return }
		historyIndex -= 1
		model.select(history[historyIndex])
	}

	private func goForward() {
		guard historyIndex < history.count - 1 else { return }
		historyIndex += 1
		model.select(history[historyIndex])
	}

	private func record(_ selection: PreferencesSelection) {
		if history.indices.contains(historyIndex), history[historyIndex] == selection {
			return
		}
		if historyIndex < history.count - 1 {
			history.removeSubrange((historyIndex + 1) ..< history.endIndex)
		}
		history.append(selection)
		historyIndex = history.count - 1
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
		case .defaultIRCopMessages: PreferencesIRCopMessagesSections(model: model)
		case .defaultIdentity: PreferencesDefaultIdentitySections(model: model)
		case .fileTransfers: PreferencesFileTransfersSections(model: model)
		case .floodControl: PreferencesFloodControlSections(model: model)
		case .hidden: PreferencesHiddenSections(model: model)
		case .incomingData: PreferencesIncomingDataSections(model: model)
		case .logLocation: PreferencesLogLocationSections(model: model)
		default: EmptyView()
		}
	}
}

/// Maps a pane identifier onto the view that answers to it.
struct PreferencesPaneRouter: View {
	/// Plugin ABI exposes an `NSView`; first-party panes use it only as the
	/// adapter around their SwiftUI content.
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
		case .controls: PreferencesControlsPane(model: model)
		case .defaultIRCopMessages: PreferencesIRCopMessagesPane(model: model)
		case .defaultIdentity: PreferencesDefaultIdentityPane(model: model)
		case .fileTransfers: PreferencesFileTransfersPane(model: model)
		case .floodControl: PreferencesFloodControlPane(model: model)
		case .general: PreferencesGeneralPane(model: model)
		case .hidden: PreferencesHiddenPane(model: model)
		case .highlights: PreferencesHighlightsPane(model: model)
		case .incomingData: PreferencesIncomingDataPane(model: model)
		case .interface: PreferencesInterfacePane(model: model)
		case .ircv3: PreferencesIRCv3Pane(model: model)
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
