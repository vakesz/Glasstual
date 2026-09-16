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
struct SettingsRootView: View {
	@Bindable var model: SettingsModel
	@Environment(\.openURL) private var openURL

	private var selection: Binding<SettingsSelection?> {
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
			.navigationTitle(Text(.Settings.accessibilityLabelSettings))
			/* The sidebar is pinned open, so the toggle a split view adds by
			 default is a button that can never do anything. This belongs on the
			 column's content: on the split view itself it does nothing. */
			.toolbar(removing: .sidebarToggle)
			.navigationSplitViewColumnWidth(SettingsMetrics.sidebarWidth)
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
			minWidth: SettingsMetrics.minimumWindowSize.width,
			idealWidth: SettingsMetrics.windowSize.width,
			minHeight: SettingsMetrics.minimumWindowSize.height,
			idealHeight: SettingsMetrics.windowSize.height
		)
		.fileImporter(
			isPresented: PendingFileRequest<SettingsImportRequest>.presentation($model.fileRequest),
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
			SettingsFontPicker(
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
			SettingsDestinationView(model: model, destination: destination)
				.navigationTitle(destination.title)
		} else {
			ContentUnavailableView(
				String(localized: .Settings.noSelectionTitle),
				systemImage: "gearshape",
				description: Text(.Settings.noSelectionMessage)
			)
			.navigationTitle(Text(.Settings.accessibilityLabelSettings))
		}
	}
}

/** What one sidebar row shows, drawn as one form whose sections carry the
 names of the settings they gather. */
private struct SettingsDestinationView: View {
	let model: SettingsModel
	let destination: SettingsDestination

	var body: some View {
		SettingsPaneLayout {
			switch destination.selection {
			case .general: GeneralPane(model: model)
			case .controls: ControlsPane(model: model)
			case .interface: InterfacePane(model: model)
			case .style: StylePane(model: model)
			case .notifications: NotificationsPane(model: model)
			case .highlights: HighlightsPane(model: model)
			case .rules: RulesPane()
			case .identity: IdentityPane(model: model)
			case .commands: CommandsPane(model: model)
			case .connection: ConnectionPane(model: model)
			case .ircv3: IRCv3Pane(model: model)
			case .fileTransfers: FileTransfersPane(model: model)
			case .advanced: AdvancedPane(model: model)
			}
		}
	}
}
