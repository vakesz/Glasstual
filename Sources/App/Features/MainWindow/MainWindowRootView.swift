/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import CocoaExtensions
import Observation
import os
import SwiftUI
import UniformTypeIdentifiers

private let mainWindowRootViewLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "MainWindowRootView"
)

@MainActor
@Observable
final class MainWindowPresentationModel {
	var isServerListVisible = true
	var isMemberListAvailable = false
	var isMemberListVisible = true
	var transcript: LogView?
	var appearanceRevision = 0
	var isChoosingTransferFiles = false
	var preferencesImportRequest = PendingFileRequest<Void>()
	var isExportingPreferencesArchive = false
	var isChoosingPreferencesExportOptions = false
	var preferencesArchiveDocument: PreferencesPropertyListDocument?
	let preferencesTransfer = PreferencesTransferSession.shared
	var inputPrompt: InputPromptPresentation?
	/** Mirrors the toolbar search field's focus. The root view keeps it in step
	 with its `@FocusState` in both directions, so setting it is what moves the
	 keyboard into the field and clicking away is what clears it. */
	var isSearchFieldFocused = false
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

	/// Puts the keyboard in the sidebar filter field, which now lives in the
	/// window toolbar. Channel Spotlight has a command of its own.
	func focusSearchField() {
		isSearchFieldFocused = true
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
		switch result {
		case let .success(urls):
			transferFileSelection?(urls)
		case let .failure(error):
			mainWindowRootViewLogger.error("Choosing files to transfer failed: \(error)")
		}
	}

	func requestPreferencesImport() {
		guard preferencesImportRequest.request == nil, preferencesTransfer.canStart else { return }
		preferencesTransfer.host = .mainWindow
		preferencesImportRequest.present()
	}

	func completePreferencesImport(_ result: Result<URL, Error>, requestID: UUID) {
		guard preferencesImportRequest.complete(requestID) != nil else { return }
		switch result {
		case let .success(url):
			Task { await preferencesTransfer.prepareImport(from: url) }
		case let .failure(error): preferencesTransfer.report(error)
		}
	}

	func requestPreferencesExport() {
		guard preferencesTransfer.canStart,
		      !isExportingPreferencesArchive, !isChoosingPreferencesExportOptions else { return }
		preferencesTransfer.host = .mainWindow
		isChoosingPreferencesExportOptions = true
	}

	func exportPreferences(includeConnectCommands: Bool) {
		Task { @MainActor in
			do {
				preferencesArchiveDocument = try await PreferencesPropertyListDocument(data: preferencesTransfer
					.exportData(includeConnectCommands: includeConnectCommands))
				isExportingPreferencesArchive = true
			} catch { preferencesTransfer.report(error) }
		}
	}

	func completePreferencesExport(_ result: Result<URL, Error>) {
		preferencesArchiveDocument = nil
		preferencesTransfer.completeExport(result)
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

	@Bindable var serverList: ServerList
	let memberList: MemberList
	let inputContentView: MainWindowTextViewContentView

	@FocusState private var isSearchFieldFocused: Bool
	@State private var memberListWidth = CGFloat(Preferences.MainWindow.memberListWidth.value)

	var body: some View {
		let preferencesImportRequestID = model.preferencesImportRequest.request?.id
		ZStack {
			NavigationSplitView(columnVisibility: serverListVisibility) {
				serverSidebar
					.navigationSplitViewColumnWidth(
						min: MainWindowConstants.serverListMinimumWidth,
						ideal: MainWindowConstants.serverListIdealWidth,
						max: MainWindowConstants.serverListMaximumWidth
					)
			} detail: {
				/* Beside the conversation, not in a split of its own. Presenting the
				 member list as an inspector, or as a second `HSplitView` pane,
				 inserts a pane into the detail column, and the column then grows
				 by the pane's width instead of sharing its space: the columns
				 spilled past the window, or AppKit gave up after three hundred
				 layout passes with the transcript left at whatever width the loop
				 was passing through. A stack inside the column changes nothing
				 the split view measures, so the divider carries its own drag. */
				HStack(spacing: 0) {
					conversation
						.frame(
							minWidth: MainWindowConstants.conversationMinimumWidth,
							maxWidth: .infinity,
							maxHeight: .infinity
						)
					if model.isMemberListAvailable, model.isMemberListVisible {
						MemberListResizeHandle(width: $memberListWidth)
						MemberListView(model: memberList, redirectTyping: redirectTyping)
							.frame(width: memberListWidth)
							/* The list paints no ground of its own; the column's is
							 the conversation's, so the divider is the only edge. */
							.background(conversationBackground)
					}
				}
			}
			/* On the split view rather than on the sidebar: `.sidebar` placement
			 draws the field above the server list, and the window's toolbar is
			 where the user looks for it. */
			.searchable(
				text: $serverList.filterText,
				placement: .toolbar,
				prompt: Text(MainWindowStrings.InputBar.searchChannels)
			)
			.searchFocused($isSearchFieldFocused)
			.disabled(loadingScreen.viewIsVisible)
			.opacity(loadingScreen.viewIsVisible ? 0 : 1)

			if loadingScreen.viewIsVisible {
				MainWindowLoadingContent(model: loadingScreen)
					.transition(.opacity)
			}
		}
		.toolbar {
			/* No sidebar toggle is declared here: the split view contributes its
			 own where the system wants it, and re-declaring it only moved it. */
			if model.isMemberListAvailable {
				ToolbarItem(placement: .primaryAction) {
					Button(MainWindowStrings.Toolbar.toggleMemberList, systemImage: "sidebar.right") {
						model.toggleMemberList()
					}
				}
			}
		}
		.presentedWindowToolbarStyle(.unified)
		/* Two directions: the menu command sets the model's flag to move the
		 keyboard into the field, and the field reports back so the flag still
		 reads true when the user focused it themselves. */
		.onChange(of: model.isSearchFieldFocused) { _, isFocused in
			isSearchFieldFocused = isFocused
		}
		.onChange(of: isSearchFieldFocused) { _, isFocused in
			model.isSearchFieldFocused = isFocused
		}
		.fileImporter(
			isPresented: $model.isChoosingTransferFiles,
			allowedContentTypes: [.item],
			allowsMultipleSelection: true,
			onCompletion: model.completeTransferFileSelection
		)
		.fileImporter(
			isPresented: PendingFileRequest<Void>.presentation($model.preferencesImportRequest),
			allowedContentTypes: [.propertyList]
		) { result in
			guard let preferencesImportRequestID else { return }
			model.completePreferencesImport(result, requestID: preferencesImportRequestID)
		}
		.fileExporter(
			isPresented: $model.isExportingPreferencesArchive,
			document: model.preferencesArchiveDocument,
			contentType: .propertyList,
			defaultFilename: PreferencesImportExport.defaultArchiveFilename,
			onCompletion: model.completePreferencesExport
		)
		.modifier(PreferencesTransferPresentation(session: model.preferencesTransfer, host: .mainWindow))
		.modifier(PreferencesExportOptionsPresentation(
			isPresented: $model.isChoosingPreferencesExportOptions,
			export: model.exportPreferences
		))
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
				.background(.bar)
		}
	}

	private var sidebarFooter: some View {
		HStack(spacing: 6) {
			Menu {
				Button(MenuStrings.Server.addServer, systemImage: "server.rack") {
					model.addServer()
				}
				Button(MenuStrings.Server.addChannel, systemImage: "number") {
					model.addChannel()
				}
			} label: {
				Image(systemName: "plus")
			}
			.menuStyle(.borderlessButton)
			.help(MainWindowStrings.InputBar.addServerOrChannel)

			Spacer(minLength: 8)

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

	/** The transcript fills the column and the input bar floats over its foot.
	 The transcript keeps the bar's height clear as its scroll view's bottom
	 content inset, and it measures that in AppKit: the field's frame plus the
	 capsule padding above it, and the accessory strip's height from what the
	 strip is showing. Nothing here reads SwiftUI's layout back into state. An
	 `onGeometryChange` on the bar did, and a size read during layout that then
	 changes the view tree sends the split view back to measure the column; it
	 lays the bar out at its probe sizes on the way, those are reported too, and
	 the loop never settles: the columns were drawn at whatever width it was
	 passing through, and AppKit threw after three hundred passes. A
	 `safeAreaInset` is the same loop through a different door. */
	private var conversation: some View {
		VStack(spacing: 0) {
			TranscriptHistoryRecoveryView(controller: model.transcript?.viewController)
			ZStack(alignment: .bottom) {
				MainWindowTranscriptRepresentable(
					logView: model.transcript,
					inputField: inputContentView,
					accessoryHeight: MainWindowInputBarLayout.accessoryHeight(
						for: inputContentView.textView.accessoryModel
					)
				)
				.id(model.appearanceRevision)

				inputBar
			}
		}
		.background(conversationBackground)
	}

	/** The reply banner and the field are two glass shapes over the same ground,
	 so they share one container and sample one backdrop. The zero spacing keeps
	 them from merging: they carry different shapes and insets, and a blend
	 between the two reads as a smear rather than as one control. */
	private var inputBar: some View {
		GlassEffectContainer(spacing: 0) {
			VStack(spacing: 0) {
				MainWindowInputAccessoryView(model: inputContentView.textView.accessoryModel) {
					inputContentView.textView.focus()
				}
				.padding(.horizontal, 18)

				MainWindowInputRepresentable(contentView: inputContentView)
					.frame(minHeight: 35, idealHeight: 44)
					.padding(.horizontal, 10)
					.padding(.vertical, MainWindowInputBarLayout.fieldVerticalPadding)
					.glassEffect(.regular, in: .capsule)
					.padding(.horizontal, 8)
					.padding(.bottom, MainWindowInputBarLayout.bottomPadding)
			}
		}
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
			/* Every hosted sheet is sized by its own content: `.fitted` asks for
			 the content's ideal size and leaves the user free to drag the sheet
			 anywhere between the content's minimum and maximum. */
			.presentationSizing(.fitted)
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

	/** Width from SwiftUI, height from the field.

	 The field's height is a constraint its text view moves as the text grows,
	 and that is what the column should follow. Its width, left to SwiftUI's
	 default measurement of an AppKit view, comes back as whatever it was last
	 laid out at, and the split view reads that as the column's minimum: the
	 column could then never shrink to make room for the member list, and the
	 columns spilled past the window's edges. */
	func sizeThatFits(
		_ proposal: ProposedViewSize,
		nsView: MainWindowTextViewContentView,
		context _: Context
	) -> CGSize? {
		CGSize(
			width: proposal.width ?? MainWindowConstants.conversationMinimumWidth,
			height: nsView.fittingSize.height
		)
	}
}

/** The fixed distances the input bar is built from. The transcript's inset
 is the field's frame -- which already includes `bottomPadding` and the padding
 below the field -- plus `fieldVerticalPadding` for the capsule's top, plus the
 accessory strip; adding `bottomPadding` to it counts that edge twice. */
enum MainWindowInputBarLayout {
	/// Above and below the field, inside the capsule.
	static let fieldVerticalPadding: CGFloat = 6
	/// Between the capsule and the column's foot; SwiftUI's side only.
	static let bottomPadding: CGFloat = 6
	static let replyBannerHeight: CGFloat = 30
	static let typingRowHeight: CGFloat = 18
	static let accessorySpacing: CGFloat = 4

	static func accessoryHeight(replyVisible: Bool, typingVisible: Bool) -> CGFloat {
		var height: CGFloat = 0
		if replyVisible {
			height += replyBannerHeight
		}
		if typingVisible {
			height += typingRowHeight
		}
		if replyVisible, typingVisible {
			height += accessorySpacing
		}
		return height
	}

	static func accessoryHeight(for model: MainWindowInputAccessoryModel) -> CGFloat {
		accessoryHeight(
			replyVisible: model.replyMessageIdentifier != nil,
			typingVisible: model.typingNicknames.isEmpty == false
		)
	}
}

/** The edge between the conversation and the member list: a divider the user
 can drag, with the width it settles on kept across launches. */
private struct MemberListResizeHandle: View {
	@Binding var width: CGFloat
	@State private var widthAtDragStart: CGFloat?

	var body: some View {
		Divider()
			.frame(width: 7)
			.contentShape(Rectangle())
			.onHover { hovering in
				if hovering {
					NSCursor.resizeLeftRight.push()
				} else {
					NSCursor.pop()
				}
			}
			.gesture(
				DragGesture(minimumDistance: 1)
					.onChanged { value in
						let start = widthAtDragStart ?? width
						widthAtDragStart = start
						width = min(
							MainWindowConstants.memberListMaximumWidth,
							max(MainWindowConstants.memberListMinimumWidth, start - value.translation.width)
						)
					}
					.onEnded { _ in
						widthAtDragStart = nil
						Preferences.MainWindow.memberListWidth.value = Double(width)
					}
			)
	}
}

struct MainWindowTranscriptRepresentable: NSViewRepresentable {
	let logView: LogView?
	/// The field floating over the transcript's foot, measured for the inset.
	var inputField: MainWindowTextViewContentView?
	/// Height of the accessory strip above the field, from what it is showing.
	var accessoryHeight: CGFloat = 0

	func makeNSView(context _: Context) -> MainWindowTranscriptHostView {
		let host = MainWindowTranscriptHostView()
		host.show(logView, inputField: inputField, accessoryHeight: accessoryHeight)
		return host
	}

	func updateNSView(_ host: MainWindowTranscriptHostView, context _: Context) {
		host.show(logView, inputField: inputField, accessoryHeight: accessoryHeight)
	}

	/** The column is SwiftUI's to size; the transcript takes what it is offered.

	 Left to the default, SwiftUI measures an AppKit view by its Auto Layout
	 fitting size, and the transcript's is whatever its topic bar happens to
	 measure: a few dozen points with no topic, the width of the whole topic on
	 one line with one. The split view then reads that as the detail column's
	 minimum and ideal width, which is how the transcript ended up drawn as a
	 strip a few characters wide beside the member list, and how a long topic
	 pushed the columns out past the window. With no height on offer the answer
	 is zero: the transcript has no height of its own to ask for, the column's
	 ideal height is then the input bar's, and the window decides the rest. */
	func sizeThatFits(
		_ proposal: ProposedViewSize,
		nsView _: MainWindowTranscriptHostView,
		context _: Context
	) -> CGSize? {
		CGSize(width: proposal.width ?? MainWindowConstants.conversationMinimumWidth, height: proposal.height ?? 0)
	}
}

final class MainWindowTranscriptHostView: NSView {
	private weak var logView: LogView?
	private weak var inputField: MainWindowTextViewContentView?
	private var accessoryHeight: CGFloat = 0

	func show(
		_ nextLogView: LogView?,
		inputField nextInputField: MainWindowTextViewContentView?,
		accessoryHeight nextAccessoryHeight: CGFloat
	) {
		defer {
			accessoryHeight = nextAccessoryHeight
			updateBottomInset()
		}
		if inputField !== nextInputField {
			inputField?.frameDidChange = nil
			inputField = nextInputField
			nextInputField?.frameDidChange = { [weak self] in
				self?.updateBottomInset()
			}
		}
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

	override func layout() {
		super.layout()
		updateBottomInset()
	}

	/** The space beneath the transcript that the input bar covers: from this
	 view's foot up to the field's top edge, then the capsule's padding above
	 the field and the accessory strip. It runs on every layout pass and on
	 every move of the field, and that is safe because it writes no SwiftUI
	 state: the transcript ignores an unchanged inset, and a changed one
	 dirties the transcript alone, not this view. A field that is not in this
	 window yet -- it is re-hosted when the appearance changes -- keeps the
	 inset it had rather than pulling the transcript under the bar and back. */
	private func updateBottomInset() {
		guard let logView, let inputField, let window, inputField.window === window else { return }
		let fieldFrame = inputField.convert(inputField.bounds, to: self)
		let fieldTop = isFlipped ? bounds.maxY - fieldFrame.minY : fieldFrame.maxY
		logView.setBottomContentInset(
			max(0, fieldTop) + MainWindowInputBarLayout.fieldVerticalPadding + accessoryHeight
		)
	}
}
