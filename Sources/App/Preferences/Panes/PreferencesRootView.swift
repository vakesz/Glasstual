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

import GlasstualPluginKit
import SwiftUI
import UniformTypeIdentifiers

/// The complete Settings interface. SwiftUI owns sidebar selection, detail
/// routing, pane layout, and presentation.
struct PreferencesRootView: View {
	@Bindable var model: PreferencesPaneModel
	@Environment(\.openURL) private var openURL

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

	/** Resolved against the section's own sub-pages rather than read straight off
	 the selection. While a section change settles, the picker can be asked to
	 draw with the incoming selection and the outgoing section's tags, and a
	 selection with no matching tag is undefined behaviour SwiftUI logs about. */
	private var selectedSubPage: Binding<String> {
		Binding(
			get: { currentSubPage?.identifier ?? subPages.first?.identifier ?? "" },
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
			/* The section list is pinned open, so the toggle a split view adds
			 by default is a button that can never do anything. This belongs on
			 the column's content: on the split view itself it does nothing. */
			.toolbar(removing: .sidebarToggle)
			.navigationSplitViewColumnWidth(
				min: PreferencesLayout.sidebarWidth,
				ideal: PreferencesLayout.sidebarWidth,
				max: PreferencesLayout.sidebarWidth + 40
			)
		} detail: {
			detail
		}
		.navigationSplitViewStyle(.balanced)
		/* The Settings window takes its size from here and nowhere else. The
		 infinite maxima are what make it resizable: with a minimum alone the
		 content refuses to grow and the window has nothing to resize into. */
		.frame(
			minWidth: PreferencesLayout.minimumWindowSize.width,
			idealWidth: PreferencesLayout.windowSize.width,
			maxWidth: .infinity,
			minHeight: PreferencesLayout.minimumWindowSize.height,
			idealHeight: PreferencesLayout.windowSize.height,
			maxHeight: .infinity
		)
		.fileImporter(
			isPresented: importIsPresented,
			allowedContentTypes: model.importRequest?.allowedContentTypes ?? [.data]
		) { result in
			model.completeImport(result)
		}
		.fileExporter(
			isPresented: exportIsPresented,
			document: model.exportedThemeData.map(PreferencesPropertyListDocument.init(data:)),
			contentType: .propertyList,
			defaultFilename: model.exportedThemeFilename
		) { result in
			model.completeExport(result)
		}
		.alert(
			TranscriptThemeStrings.themeError,
			isPresented: errorIsPresented,
			actions: {
				Button(PromptStrings.Action.confirmation) { model.presentationError = nil }
			},
			message: {
				Text(verbatim: model.presentationError ?? "")
			}
		)
		.sheet(isPresented: $model.showsFontPicker) {
			PreferencesFontPicker(
				fontName: model.transcriptTheme.fontName,
				fontSize: model.transcriptTheme.fontSize,
				apply: model.applyChannelViewFont
			)
		}
		.onChange(of: model.externalURL) { _, url in
			guard let url else { return }
			openURL(url)
			model.externalURL = nil
		}
	}

	private var importIsPresented: Binding<Bool> {
		Binding(
			get: { model.importRequest != nil },
			set: {
				if $0 == false {
					model.importRequest = nil
				}
			}
		)
	}

	private var exportIsPresented: Binding<Bool> {
		Binding(
			get: { model.exportedThemeData != nil },
			set: {
				if $0 == false {
					model.exportedThemeData = nil
				}
			}
		)
	}

	private var errorIsPresented: Binding<Bool> {
		Binding(
			get: { model.presentationError != nil },
			set: {
				if $0 == false {
					model.presentationError = nil
				}
			}
		)
	}

	private var detail: some View {
		VStack(spacing: 0) {
			if let section = model.currentSection {
				/* Identified by its section, so that moving to another one
				 rebuilds the picker rather than updating one whose tags still
				 belong to the section being left. */
				PreferencesSubPagePicker(
					sectionTitle: section.title,
					subPages: section.subPages,
					selection: selectedSubPage
				)
				.id(section.identifier)
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
}

/// When a section's sub-page picker can be drawn at all.
enum PreferencesSubPagePickerPolicy {
	/** A picker needs more than one segment to be worth drawing, and it needs a
	 selection one of those segments carries as its tag: SwiftUI reports a
	 selection with no matching tag as undefined and draws nothing sensible. */
	static func drawsPicker(subPageIdentifiers: [String], selection: String) -> Bool {
		subPageIdentifiers.count > 1 && subPageIdentifiers.contains(selection)
	}
}

/** The segmented row that picks between one section's sub-pages.

 It keeps to the form's own width so no section can push the window wider, and
 a section with more sub-pages than a segmented row holds lists them in a
 pop-up instead. */
private struct PreferencesSubPagePicker: View {
	let sectionTitle: String
	let subPages: [PreferencesSubPage]
	@Binding var selection: String

	var body: some View {
		if PreferencesSubPagePickerPolicy.drawsPicker(
			subPageIdentifiers: subPages.map(\.identifier),
			selection: selection
		) {
			pickerContent
				.frame(maxWidth: .infinity)
				.padding(.horizontal, PreferencesLayout.contentInset)
				.padding(.top, 14)
		}
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
		Picker(selection: $selection) {
			ForEach(subPages) { subPage in
				Text(verbatim: subPage.title).tag(subPage.identifier)
			}
		} label: {
			EmptyView()
		}
		.labelsHidden()
		.accessibilityLabel(Text(verbatim: sectionTitle))
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
	/// Plugin panes are SwiftUI values, so the Settings scene owns their layout.
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
		if plugins.indices.contains(index), let pane = plugins[index].pluginPreferencesPane {
			pane.makeView()
				.frame(minHeight: Self.pluginPaneHeight)
				.padding(20)
		}
	}
}
