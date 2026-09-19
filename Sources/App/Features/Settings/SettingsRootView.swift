// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Observation
import SwiftUI
import UniformTypeIdentifiers

enum SettingsSceneSelection: UInt, Sendable {
	case `default`
	case notifications
	case style
	case hiddenSettings
}

@MainActor
@Observable
final class SettingsSceneRequest {
	private(set) var selection: SettingsSceneSelection = .default
	private(set) var revision = 0

	func open(_ selection: SettingsSceneSelection) {
		self.selection = selection
		revision &+= 1
	}
}

/// The `Settings` scene, as a named type like every other application scene.
struct SettingsScene: Scene {
	let request: SettingsSceneRequest

	var body: some Scene {
		Settings {
			SettingsSceneRoot(request: request)
		}
		/* The pages declare their own minimum, and the window used to let
		 itself be dragged narrower than any of them could lay out. */
		.windowResizability(.contentMinSize)
	}
}

private struct SettingsSceneRoot: View {
	let request: SettingsSceneRequest
	@State private var model = SettingsModel()

	var body: some View {
		/* No frame here: `SettingsRootView` declares the window's minimum,
		 ideal and maximum size, and a second frame would only fight it. */
		SettingsRootView(model: model)
			.onAppear {
				model.activate(selection: request.selection)
			}
			.onChange(of: request.revision) {
				model.activate(selection: request.selection)
			}
			.onDisappear {
				model.deactivate()
			}
	}
}

/// The complete Settings interface. SwiftUI owns sidebar selection, detail
/// routing, pane layout, and presentation.
struct SettingsRootView: View {
	@Bindable var model: SettingsModel
	@Environment(\.openURL) private var openURL

	private var selection: Binding<SettingsPane?> {
		Binding(
			get: { model.selection },
			set: { row in
				guard let row else { return }
				model.select(row)
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
			.navigationSplitViewColumnWidth(SettingsWindowMetrics.sidebarWidth)
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
			      model.matchingDestinations.contains(where: { row in row.id == model.selection }) == false
			else { return }
			model.select(first.id)
		}
		.modifier(SettingsTransferPresentation(session: .shared, host: .settings))
		/* The Settings window takes its size from here and nowhere else: one
		 ideal size for every pane, so moving between them does not resize the
		 window, and a floor the shortest form still draws inside. Each pane's
		 own height comes from its form, which scrolls. */
		.frame(
			minWidth: SettingsWindowMetrics.minimumWindowSize.width,
			idealWidth: SettingsWindowMetrics.windowSize.width,
			minHeight: SettingsWindowMetrics.minimumWindowSize.height,
			idealHeight: SettingsWindowMetrics.windowSize.height
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
			document: model.exportedThemeData.map(SettingsPropertyListDocument.init(data:)),
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
				apply: model.applyTranscriptFont
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

	/** One grouped, independently scrolling `Form`, with each setting a row of
	 its own: a `VStack` inside a grouped form counts as one row, so the
	 system's separators, spacing and label alignment would apply to the stack
	 rather than to the settings inside it. */
	var body: some View {
		Form {
			/* Every pane the window can show, gathered exactly as the sidebar row
			 that draws it gathers them: a row is named by its first pane, and the
			 panes it shows alongside it name the same view. */
			switch destination.id {
			case .general: GeneralPane(model: model)
			case .controls: ControlsPane(model: model)
			case .interface: InterfacePane(model: model)
			case .style: StylePane(model: model)
			case .notifications: NotificationsPane(model: model)
			case .highlights: HighlightsPane(model: model)
			case .rules: RulesPane()
			case .defaultIdentity, .defaultIRCopMessages: IdentityPane(model: model)
			case .commandScope, .channelManagement: CommandsPane(model: model)
			case .floodControl, .incomingData: ConnectionPane(model: model)
			case .ircv3: IRCv3Pane(model: model)
			case .fileTransfers: FileTransfersPane(model: model)
			case .logLocation, .hidden: AdvancedPane(model: model)
			}
		}
		.formStyle(.grouped)
		.scrollContentBackground(.hidden)
		.contentMargins(.top, UISpacing.regular, for: .scrollContent)
	}
}
