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
import UniformTypeIdentifiers

/// The complete Settings interface. SwiftUI owns sidebar selection, detail
/// routing, pane layout, and presentation.
struct PreferencesRootView: View {
	@Bindable var model: PreferencesPaneModel
	@Environment(\.openURL) private var openURL

	private var selection: Binding<PreferencesSelection?> {
		Binding(
			get: { model.selection },
			set: { destination in
				guard let destination else { return }
				model.select(destination)
			}
		)
	}

	var body: some View {
		let fileRequest = model.fileRequest.request
		return NavigationSplitView(columnVisibility: .constant(.all)) {
			/* The rows are identified by their selection, so the list needs no
			 tags: choosing one hands back the destination it stands for. */
			List(model.matchingDestinations, selection: selection) { destination in
				Label(destination.title, systemImage: destination.symbolName)
			}
			.listStyle(.sidebar)
			.scrollEdgeEffectStyle(.soft, for: .all)
			.accessibilityIdentifier("settings-sidebar")
			.navigationTitle(PreferencesStrings.accessibilityTitle)
			/* The sidebar is pinned open, so the toggle a split view adds by
			 default is a button that can never do anything. This belongs on the
			 column's content: on the split view itself it does nothing. */
			.toolbar(removing: .sidebarToggle)
			.navigationSplitViewColumnWidth(PreferencesMetrics.sidebarWidth)
			.searchable(text: $model.searchText, placement: .sidebar, prompt: .Settings.searchPlaceholder)
		} detail: {
			if model.matchingDestinations.isEmpty {
				ContentUnavailableView.search(text: model.searchText)
			} else {
				detail
			}
		}
		.navigationSplitViewStyle(.balanced)
		.onChange(of: model.searchText) {
			guard let first = model.matchingDestinations.first,
			      model.matchingDestinations.contains(where: { $0.selection == model.selection }) == false
			else { return }
			model.select(first.selection)
		}
		.modifier(PreferencesTransferPresentation(session: .shared, host: .settings))
		/* The Settings window takes its size from here and nowhere else: one
		 ideal size for every pane, so moving between them does not resize the
		 window, and a floor the shortest form still draws inside. Each pane's
		 own height comes from its form, which scrolls. */
		.frame(
			minWidth: PreferencesMetrics.minimumWindowSize.width,
			idealWidth: PreferencesMetrics.windowSize.width,
			minHeight: PreferencesMetrics.minimumWindowSize.height,
			idealHeight: PreferencesMetrics.windowSize.height
		)
		.fileImporter(
			isPresented: PendingFileRequest<PreferencesImportRequest>.presentation($model.fileRequest),
			allowedContentTypes: fileRequest?.kind.allowedContentTypes ?? [.data]
		) { result in
			guard let fileRequest, let kind = model.fileRequest.complete(fileRequest.id) else { return }
			model.completeImport(result, request: kind)
		}
		.onDisappear { model.fileRequest.reset() }
		.fileExporter(
			isPresented: exportIsPresented,
			document: model.exportedThemeData.map(PreferencesPropertyListDocument.init(data:)),
			contentType: .propertyList,
			defaultFilename: model.exportedThemeFilename
		) { result in
			model.completeExport(result)
		}
		.alert(
			model.presentationFailure?.title ?? "",
			isPresented: failureIsPresented,
			presenting: model.presentationFailure
		) { _ in
			Button(PromptStrings.Action.confirmation) { model.presentationFailure = nil }
		} message: { failure in
			Text(verbatim: failure.message)
		}
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

	private var failureIsPresented: Binding<Bool> {
		Binding(
			get: { model.presentationFailure != nil },
			set: {
				if $0 == false {
					model.presentationFailure = nil
				}
			}
		)
	}

	@ViewBuilder
	private var detail: some View {
		if let destination = model.currentDestination {
			PreferencesDestinationView(model: model, destination: destination)
				.navigationTitle(destination.title)
		} else {
			ContentUnavailableView(
				PreferencesStrings.noSelectionTitle,
				systemImage: "gearshape",
				description: Text(verbatim: PreferencesStrings.noSelectionMessage)
			)
			.navigationTitle(PreferencesStrings.accessibilityTitle)
		}
	}
}

/** What one sidebar row shows: the panes it gathers, drawn as one form whose
 sections carry the pane names. */
private struct PreferencesDestinationView: View {
	let model: PreferencesPaneModel
	let destination: PreferencesDestination

	var body: some View {
		PreferencesPaneLayout {
			ForEach(destination.panes, id: \.self) { pane in
				PreferencesPaneSections(model: model, pane: pane)
			}
		}
	}
}

/// The sections of one pane, whether its row shows it on its own or gathers it
/// with its neighbours.
private struct PreferencesPaneSections: View {
	let model: PreferencesPaneModel
	let pane: PreferencesPane

	var body: some View {
		switch pane {
		case .channelManagement: PreferencesChannelManagementSections(model: model)
		case .commandScope: PreferencesCommandScopeSections(model: model)
		case .controls: PreferencesControlsSections(model: model)
		case .defaultIRCopMessages: PreferencesIRCopMessagesSections(model: model)
		case .defaultIdentity: PreferencesDefaultIdentitySections(model: model)
		case .fileTransfers: PreferencesFileTransfersSections(model: model)
		case .floodControl: PreferencesFloodControlSections(model: model)
		case .general: PreferencesGeneralSections(model: model)
		case .hidden: PreferencesHiddenSections(model: model)
		case .highlights: PreferencesHighlightsSections(model: model)
		case .incomingData: PreferencesIncomingDataSections(model: model)
		case .interface: PreferencesInterfaceSections(model: model)
		case .ircv3: PreferencesIRCv3Sections(model: model)
		case .logLocation: PreferencesLogLocationSections(model: model)
		case .notifications: PreferencesNotificationsSections(model: model)
		case .rules: RulesSections()
		case .style: PreferencesStyleSections(model: model)
		}
	}
}
