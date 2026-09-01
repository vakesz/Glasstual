/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import CocoaExtensions
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class MainWindowPresentationModel {
	var isServerListVisible = true
	var isMemberListAvailable = false
	var isMemberListVisible = true
	var transcript: LogView?
	var appearanceRevision = 0
	var isChoosingTransferFiles = false
	var isChoosingPreferencesArchive = false
	var isExportingPreferencesArchive = false
	var preferencesArchiveDocument: PreferencesPropertyListDocument?
	var inputPrompt: InputPromptPresentation?
	private(set) var sheetStack: [MainWindowSheetPresentation] = []

	@ObservationIgnored weak var window: MainWindow?
	@ObservationIgnored private var transferFileSelection: (([URL]) -> Void)?

	func attach(to window: MainWindow) {
		precondition(self.window == nil || self.window === window)
		self.window = window
	}

	func addServer() {
		window?.menuController.addServer(nil)
	}

	func addChannel() {
		window?.menuController.addChannel(nil)
	}

	var addServerTitle: String {
		window?.menuController.mainWindowSegmentedControllerCellMenu.item(for: .segmentedAddServer)?.title
			?? MainWindowStrings.InputBar.addServerOrChannel
	}

	var addChannelTitle: String {
		window?.menuController.mainWindowSegmentedControllerCellMenu.item(for: .segmentedAddChannel)?.title
			?? MainWindowStrings.InputBar.addServerOrChannel
	}

	func searchChannels() {
		window?.menuController.showChannelSpotlightWindow(nil)
	}

	func markAllAsRead() {
		window?.menuController.markAllAsRead(nil)
	}

	func toggleNotifications() {
		window?.menuController.toggleMuteOnNotifications(nil)
	}

	func showAddressBook() {
		window?.menuController.showAddressBook(nil)
	}

	func showFileTransfers() {
		window?.menuController.showFileTransfersWindow(nil)
	}

	func showSettings() {
		window?.menuController.showPreferencesWindow(nil)
	}

	func toggleMemberList() {
		window?.toggleMemberListVisibility()
	}

	func chooseTransferFiles(perform: @escaping ([URL]) -> Void) {
		transferFileSelection = perform
		isChoosingTransferFiles = true
	}

	func completeTransferFileSelection(_ result: Result<[URL], Error>) {
		defer { transferFileSelection = nil }
		guard case let .success(urls) = result else { return }
		transferFileSelection?(urls)
	}

	func requestPreferencesImport() {
		Task { @MainActor in
			let outcome = await Alerts.run(
				AlertRequest(
					title: PromptStrings.ConfigurationTransfer.importTitle,
					body: PromptStrings.ConfigurationTransfer.importBody,
					defaultButton: PromptStrings.Action.chooseFile,
					alternateButton: PromptStrings.Action.cancel,
					style: .warning
				),
				on: .anyVisibleWindow
			)
			guard outcome.response == .default else { return }
			isChoosingPreferencesArchive = true
		}
	}

	func completePreferencesImport(_ result: Result<URL, Error>) {
		guard case let .success(url) = result else { return }
		let accessWasGranted = url.startAccessingSecurityScopedResource()
		defer {
			if accessWasGranted {
				url.stopAccessingSecurityScopedResource()
			}
		}
		PreferencesImportExport.importPostflight(url)
	}

	func requestPreferencesExport() {
		Task { @MainActor in
			let outcome = await Alerts.run(
				AlertRequest(
					title: PromptStrings.ConfigurationTransfer.exportTitle,
					body: PromptStrings.ConfigurationTransfer.exportBody,
					defaultButton: PromptStrings.ConfigurationTransfer.exportButtonTitle,
					alternateButton: PromptStrings.Action.cancel,
					style: .warning
				),
				on: .anyVisibleWindow
			)
			guard outcome.response == .default,
			      let data = PreferencesImportExport.exportedPreferencesData(filterJunk: true)
			else { return }
			preferencesArchiveDocument = PreferencesPropertyListDocument(data: data)
			isExportingPreferencesArchive = true
		}
	}

	func completePreferencesExport(_: Result<URL, Error>) {
		preferencesArchiveDocument = nil
	}

	func presentInputPrompt(
		_ request: InputPromptRequest,
		completion: @escaping @MainActor (InputPromptOutcome) -> Void
	) {
		inputPrompt?.finish(.cancelled)
		inputPrompt = InputPromptPresentation(request: request, completion: completion)
	}

	func completeInputPrompt(_ outcome: InputPromptOutcome) {
		guard let inputPrompt else { return }
		inputPrompt.finish(outcome)
		self.inputPrompt = nil
	}

	func inputPromptDidDismiss() {
		guard let inputPrompt else { return }
		inputPrompt.finish(.cancelled)
		self.inputPrompt = nil
	}

	func presentSheet(_ presentation: MainWindowSheetPresentation) {
		sheetStack.append(presentation)
	}

	func dismissSheet(ownedBy owner: AnyObject) {
		guard let index = sheetStack.firstIndex(where: { $0.owner === owner }) else { return }
		dismissSheets(startingAt: index)
	}

	func dismissPresentedSheet() {
		dismissSheets(startingAt: 0)
	}

	func sheet(at index: Int) -> MainWindowSheetPresentation? {
		guard sheetStack.indices.contains(index) else { return nil }
		return sheetStack[index]
	}

	func sheetOwner<Owner>(ofType _: Owner.Type) -> Owner? {
		sheetStack.lazy.compactMap { $0.owner as? Owner }.first
	}

	func closeSheets(where shouldClose: (AnyObject) -> Bool) {
		guard let index = sheetStack.firstIndex(where: { shouldClose($0.owner) }) else { return }
		dismissSheets(startingAt: index)
	}

	func closePresentedSheet() {
		if sheetStack.isEmpty == false {
			dismissPresentedSheet()
		} else {
			window?.attachedSheet?.close()
		}
	}

	func dismissSheets(startingAt index: Int) {
		guard sheetStack.indices.contains(index) else { return }
		for presentation in sheetStack[index...].reversed() {
			presentation.finish()
		}
		sheetStack.removeSubrange(index...)
	}
}

struct MainWindowRootView: View {
	@Bindable var model: MainWindowPresentationModel
	@Bindable var loadingScreen: MainWindowLoadingScreen

	let serverList: ServerList
	let memberList: MemberList
	let inputContentView: MainWindowTextViewContentView

	var body: some View {
		ZStack {
			NavigationSplitView(columnVisibility: serverListVisibility) {
				serverSidebar
					.navigationSplitViewColumnWidth(
						min: MainWindowConstants.serverListMinimumWidth,
						ideal: MainWindowConstants.serverListIdealWidth,
						max: MainWindowConstants.serverListMaximumWidth
					)
			} detail: {
				HSplitView {
					conversation
						.frame(
							minWidth: MainWindowConstants.conversationMinimumWidth,
							maxWidth: .infinity,
							maxHeight: .infinity
						)

					if model.isMemberListAvailable, model.isMemberListVisible {
						MemberListView(model: memberList, redirectTyping: redirectTyping)
							.frame(
								minWidth: MainWindowConstants.memberListMinimumWidth,
								idealWidth: MainWindowConstants.memberListIdealWidth,
								maxWidth: MainWindowConstants.memberListMaximumWidth
							)
					}
				}
			}
			.disabled(loadingScreen.viewIsVisible)
			.opacity(loadingScreen.viewIsVisible ? 0 : 1)

			if loadingScreen.viewIsVisible {
				MainWindowLoadingContent(model: loadingScreen)
					.transition(.opacity)
			}
		}
		.toolbar {
			DefaultToolbarItem(kind: .sidebarToggle, placement: .navigation)

			if model.isMemberListAvailable {
				ToolbarItem(placement: .primaryAction) {
					Button(MainWindowStrings.Toolbar.toggleMemberList, systemImage: "sidebar.right") {
						model.toggleMemberList()
					}
				}
			}
		}
		.presentedWindowToolbarStyle(.unified)
		.fileImporter(
			isPresented: $model.isChoosingTransferFiles,
			allowedContentTypes: [.item],
			allowsMultipleSelection: true,
			onCompletion: model.completeTransferFileSelection
		)
		.fileImporter(
			isPresented: $model.isChoosingPreferencesArchive,
			allowedContentTypes: [.propertyList],
			onCompletion: model.completePreferencesImport
		)
		.fileExporter(
			isPresented: $model.isExportingPreferencesArchive,
			document: model.preferencesArchiveDocument,
			contentType: .propertyList,
			defaultFilename: PreferencesImportExport.defaultArchiveFilename,
			onCompletion: model.completePreferencesExport
		)
		.sheet(item: $model.inputPrompt, onDismiss: model.inputPromptDidDismiss) { prompt in
			InputPromptView(
				presentation: prompt,
				submit: {
					model.completeInputPrompt(.submitted(prompt.value))
				},
				cancel: {
					model.completeInputPrompt(.cancelled)
				}
			)
		}
		.sheet(isPresented: rootSheetIsPresented) {
			if let presentation = model.sheet(at: 0) {
				MainWindowSheetHost(model: model, presentation: presentation, index: 0)
			}
		}
	}

	private var serverListVisibility: Binding<NavigationSplitViewVisibility> {
		Binding(
			get: { model.isServerListVisible ? .all : .detailOnly },
			set: { model.isServerListVisible = $0 != .detailOnly }
		)
	}

	private var rootSheetIsPresented: Binding<Bool> {
		Binding(
			get: { model.sheetStack.isEmpty == false },
			set: { isPresented in
				if isPresented == false {
					model.dismissPresentedSheet()
				}
			}
		)
	}

	private var serverSidebar: some View {
		VStack(spacing: 0) {
			ServerListView(model: serverList, redirectTyping: redirectTyping)
			Divider()
			sidebarFooter
		}
	}

	private var sidebarFooter: some View {
		HStack(spacing: 6) {
			Menu {
				Button(model.addServerTitle, systemImage: "server.rack") {
					model.addServer()
				}
				Button(model.addChannelTitle, systemImage: "number") {
					model.addChannel()
				}
			} label: {
				Image(systemName: "plus")
			}
			.menuStyle(.borderlessButton)
			.help(MainWindowStrings.InputBar.addServerOrChannel)

			Spacer(minLength: 8)

			Button(MainWindowStrings.InputBar.searchChannels, systemImage: "magnifyingglass") {
				model.searchChannels()
			}
			.labelStyle(.iconOnly)
			.buttonStyle(.borderless)
			.help(MainWindowStrings.InputBar.searchChannels)

			Menu {
				Button(MainWindowStrings.InputBar.markAllAsRead, systemImage: "checkmark.circle") {
					model.markAllAsRead()
				}
				Button(MainWindowStrings.InputBar.disableAllNotifications, systemImage: "bell.slash") {
					model.toggleNotifications()
				}
				Divider()
				Button(MainWindowStrings.InputBar.addressBook, systemImage: "person.crop.circle") {
					model.showAddressBook()
				}
				Button(MainWindowStrings.InputBar.fileTransfers, systemImage: "arrow.down.circle") {
					model.showFileTransfers()
				}
				Divider()
				Button(MainWindowStrings.InputBar.hideMemberList, systemImage: "sidebar.right") {
					model.toggleMemberList()
				}
				Button(MainWindowStrings.InputBar.settings, systemImage: "gear") {
					model.showSettings()
				}
			} label: {
				Image(systemName: "ellipsis.circle")
			}
			.menuStyle(.borderlessButton)
			.help(MainWindowStrings.InputBar.more)
		}
		.controlSize(.small)
		.padding(.horizontal, 10)
		.frame(height: MainWindowConstants.sidebarFooterHeight)
	}

	private var conversation: some View {
		VStack(spacing: 0) {
			MainWindowTranscriptRepresentable(logView: model.transcript)
				.id(model.appearanceRevision)

			MainWindowInputAccessoryView(model: inputContentView.textView.accessoryModel) {
				inputContentView.textView.focus()
			}
			.padding(.horizontal, 18)

			MainWindowInputRepresentable(contentView: inputContentView)
				.frame(minHeight: 35, idealHeight: 44)
				.padding(.horizontal, 10)
				.padding(.vertical, 6)
				.background(.regularMaterial, in: Capsule())
				.padding(.horizontal, 8)
				.padding(.bottom, 6)
		}
		.background(conversationBackground)
	}

	private var conversationBackground: Color {
		_ = model.appearanceRevision
		return Color(nsColor: SharedApplication.sharedThemeController().backgroundColor)
	}

	private func redirectTyping(_ text: String) {
		let textView = inputContentView.textView
		textView.focus()
		textView.insertText(text, replacementRange: textView.selectedRange())
	}
}

private struct MainWindowSheetHost: View {
	@Bindable var model: MainWindowPresentationModel
	let presentation: MainWindowSheetPresentation
	let index: Int

	var body: some View {
		presentation.content
			.sheet(isPresented: nestedSheetIsPresented) {
				if let nested = model.sheet(at: index + 1) {
					MainWindowSheetHost(model: model, presentation: nested, index: index + 1)
				}
			}
	}

	private var nestedSheetIsPresented: Binding<Bool> {
		Binding(
			get: { model.sheet(at: index + 1) != nil },
			set: { isPresented in
				if isPresented == false {
					model.dismissSheets(startingAt: index + 1)
				}
			}
		)
	}
}

enum MainWindowTypingRedirectPolicy {
	static func text(
		for characters: String,
		commandIsPressed: Bool,
		controlIsPressed: Bool
	) -> String? {
		guard commandIsPressed == false,
		      controlIsPressed == false,
		      characters.isEmpty == false,
		      characters.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) == false })
		else { return nil }

		return characters
	}
}

private struct MainWindowTypingRedirectModifier: ViewModifier {
	let action: (String) -> Void

	func body(content: Content) -> some View {
		content.onKeyPress { press in
			guard let text = MainWindowTypingRedirectPolicy.text(
				for: press.characters,
				commandIsPressed: press.modifiers.contains(.command),
				controlIsPressed: press.modifiers.contains(.control)
			) else { return .ignored }

			action(text)
			return .handled
		}
	}
}

extension View {
	func redirectsPrintableInput(to action: @escaping (String) -> Void) -> some View {
		modifier(MainWindowTypingRedirectModifier(action: action))
	}
}

private struct MainWindowInputRepresentable: NSViewRepresentable {
	let contentView: MainWindowTextViewContentView

	func makeNSView(context _: Context) -> MainWindowTextViewContentView {
		contentView.removeFromSuperview()
		return contentView
	}

	func updateNSView(_: MainWindowTextViewContentView, context _: Context) {}
}

struct MainWindowTranscriptRepresentable: NSViewRepresentable {
	let logView: LogView?

	func makeNSView(context _: Context) -> MainWindowTranscriptHostView {
		let host = MainWindowTranscriptHostView()
		host.show(logView)
		return host
	}

	func updateNSView(_ host: MainWindowTranscriptHostView, context _: Context) {
		host.show(logView)
	}
}

final class MainWindowTranscriptHostView: NSView {
	private weak var logView: LogView?

	func show(_ nextLogView: LogView?) {
		guard logView !== nextLogView else { return }
		logView?.view.removeFromSuperview()
		logView = nextLogView

		guard let transcriptView = nextLogView?.view else { return }
		transcriptView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(transcriptView)
		NSLayoutConstraint.activate([
			transcriptView.leadingAnchor.constraint(equalTo: leadingAnchor),
			transcriptView.trailingAnchor.constraint(equalTo: trailingAnchor),
			transcriptView.topAnchor.constraint(equalTo: topAnchor),
			transcriptView.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}
}
