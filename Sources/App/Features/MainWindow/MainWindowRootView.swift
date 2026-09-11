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
	/** Mirrors the notification controller's mute switch so the footer menu can
	 name what the next press will do. The controller is not observable and the
	 switch is thrown from the main menu as well, so the coordinator that owns
	 the switch writes it here whenever it changes. */
	var areNotificationsDisabled = false
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
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@Environment(\.colorSchemeContrast) private var contrast

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
				/* Beside the conversation, not in a split of its own, and not an
				 `.inspector` either.

				 An inspector -- like a second `HSplitView` pane -- inserts a pane
				 into the detail column, and the column then grows by the pane's
				 width instead of sharing its space: the columns spilled past the
				 window, or AppKit gave up after three hundred layout passes with
				 the transcript left at whatever width the loop was passing
				 through. What feeds that loop is still here: the transcript's
				 bottom inset is measured in AppKit from the floating input bar's
				 frame, so the detail column's width decides a value that moves a
				 view inside it. A stack changes nothing the split view measures,
				 so the divider carries its own drag -- with the pointer, keyboard
				 and reset behaviour an inspector's divider would have given it. */
				HStack(spacing: 0) {
					conversation
						.frame(
							minWidth: MainWindowConstants.conversationMinimumWidth,
							maxWidth: .infinity,
							maxHeight: .infinity
						)
					if model.isMemberListAvailable, model.isMemberListVisible {
						MemberListResizeHandle(width: $memberListWidth)
						/* The rows scroll up into the titlebar's safe area and
						 the system's soft edge effect is what keeps the toolbar
						 legible over them, so nothing here insets the list by
						 hand. The list paints no ground of its own; the column's
						 is the conversation's, so the divider is the only edge. */
						MemberListView(model: memberList, redirectTyping: redirectTyping)
							.scrollEdgeEffectStyle(.soft, for: .top)
							.frame(width: memberListWidth)
					}
				}
				/* One ground for both columns, up under the transparent titlebar.

				 Measured: the list's own scroll view runs the full height of the
				 window and insets its rows by the titlebar, while the transcript
				 is an `NSViewRepresentable` that SwiftUI lays out inside the safe
				 area. The two agree on where their content starts -- both at the
				 safe-area top -- and disagree only about the strip above it, so
				 each column painting its own ground left that strip in the theme
				 colour beside the list and in the window's colour beside the
				 transcript. A background changes nothing the split view measures,
				 which is what keeps this out of the layout loop the comment on
				 `conversation` describes; insetting the list to match the
				 transcript, or lifting the transcript out of the safe area, would
				 both put a column's own layout back into the column's insets. */
				.background(conversationBackground.ignoresSafeArea(.container, edges: .top))
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
					/* The title says which way the press goes and the symbol
					 says which state the window is in, the way Mail's sidebar
					 toggle does: filled while the pane is showing. */
					Button(
						MainWindowStrings.Menu.memberList(isVisible: model.isMemberListVisible),
						systemImage: model.isMemberListVisible ? "sidebar.squares.trailing" : "sidebar.trailing"
					) {
						model.toggleMemberList()
					}
					.help(MainWindowStrings.Menu.memberList(isVisible: model.isMemberListVisible))
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

	/** Two icon-only controls at the sidebar's foot.

	 The `plus` is Notes' New Folder button: a press adds a channel, a press and
	 hold offers the whole list. It used to be a plain menu with the indicator
	 hidden, which reads as an immediate action and then is not one. The
	 overflow menu keeps its indicator hidden -- `ellipsis.circle` already says
	 there is more behind it -- and neither icon is permanently dimmed any
	 longer: secondary foreground on a control that is not disabled reads as
	 disabled. */
	private var sidebarFooter: some View {
		HStack(spacing: UISpacing.tight) {
			Menu {
				Button(MenuStrings.Server.addServer, systemImage: "server.rack") {
					model.addServer()
				}
				Button(MenuStrings.Server.addChannel, systemImage: "number") {
					model.addChannel()
				}
			} label: {
				footerIcon("plus")
			} primaryAction: {
				model.addChannel()
			}
			.sidebarFooterMenu()
			.help(MainWindowStrings.InputBar.addServerOrChannel)

			Spacer(minLength: UISpacing.regular)

			Menu {
				Button(MainWindowStrings.InputBar.markAllAsRead, systemImage: "checkmark.circle") {
					model.markAllAsRead()
				}
				Button(
					MainWindowStrings.Menu.notifications(areDisabled: model.areNotificationsDisabled),
					systemImage: model.areNotificationsDisabled ? "bell" : "bell.slash"
				) {
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
				Button(
					MainWindowStrings.Menu.memberList(isVisible: model.isMemberListVisible),
					systemImage: model.isMemberListVisible ? "sidebar.squares.trailing" : "sidebar.trailing"
				) {
					model.toggleMemberList()
				}
				.disabled(model.isMemberListAvailable == false)
				Button(MainWindowStrings.InputBar.settings, systemImage: "gear") {
					model.showSettings()
				}
			} label: {
				footerIcon("ellipsis.circle")
			}
			.sidebarFooterMenu()
			.menuIndicator(.hidden)
			.help(MainWindowStrings.InputBar.more)
		}
		.padding(.horizontal, UISpacing.wide)
		.frame(height: MainWindowConstants.sidebarFooterHeight)
	}

	private func footerIcon(_ systemName: String) -> some View {
		Image(systemName: systemName)
			.font(.system(size: 14, weight: .medium))
			.frame(width: MainWindowConstants.footerIconSize, height: MainWindowConstants.footerIconSize)
			.contentShape(Rectangle())
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
				/* No `.scrollEdgeEffectStyle` beside the member list's, and it is
				 not an oversight. The transcript is an AppKit `NSScrollView`
				 that this view only hosts, and the modifier is SwiftUI's: it
				 reaches SwiftUI's own scrollable content, not a scroll view
				 inside an `NSViewRepresentable`. AppKit has no equivalent -- the
				 macOS 26 SDK declares `NSScrollEdgeEffectStyle` but the only
				 public properties that take one are on
				 `NSTitlebarAccessoryViewController` and
				 `NSSplitViewItemAccessoryViewController`, and `NSScrollView`
				 exposes nothing at all -- so the transcript cannot ask for the
				 soft treatment the lists get. It also has nothing to soften: the
				 representable is laid out inside the safe area, so the
				 conversation starts below the toolbar rather than scrolling
				 under it, and the list -- whose own scroll view runs the full
				 height and insets its rows by the titlebar instead -- starts its
				 first row on the same line. `MainWindowColumnAlignmentTests`
				 measures both. Insetting this column by hand to close the
				 remaining difference is what the comment above rules out: it
				 makes the column's insets depend on the column's own layout. */
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
				/* The banner's text starts where the field's does: the capsule's
				 own inset plus the inset that holds the capsule off the column's
				 edge. */
				.padding(.horizontal, UISpacing.loose)

				MainWindowInputRepresentable(contentView: inputContentView)
					.frame(minHeight: 35, idealHeight: 44)
					.padding(.horizontal, UISpacing.regular)
					.padding(.vertical, MainWindowInputBarLayout.fieldVerticalPadding)
					.glassEffect(.regular, in: .capsule)
					.overlay(focusRing)
					.padding(.horizontal, UISpacing.regular)
					.padding(.bottom, MainWindowInputBarLayout.bottomPadding)
			}
		}
	}

	/** What says the keyboard is in the message field.

	 Glass draws no focus ring of its own and the field's own ring is turned
	 off, so nothing marked the field as the place typing would land. The
	 capsule takes the accent colour while the field holds the keyboard, drawn
	 thicker where the system asks for increased contrast. */
	private var focusRing: some View {
		Capsule()
			.strokeBorder(
				Color.accentColor,
				lineWidth: contrast == .increased
					? MainWindowConstants.focusRingWidthIncreasedContrast
					: MainWindowConstants.focusRingWidth
			)
			.opacity(inputContentView.textView.focusModel.isFocused ? 1 : 0)
			.animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: inputContentView.textView.focusModel
				.isFocused)
			.accessibilityHidden(true)
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

	/// A footer control: a bare icon as the label, with the accessory bar's
	/// hover and pressed treatment so it answers the pointer the way the rows
	/// above it do. The label style is left alone so the menu's own items keep
	/// their titles.
	func sidebarFooterMenu() -> some View {
		menuStyle(.button)
			.buttonStyle(.accessoryBar)
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

	static func accessoryHeight(replyVisible: Bool, typingVisible: Bool) -> CGFloat {
		var height: CGFloat = 0
		if replyVisible {
			height += replyBannerHeight
		}
		if typingVisible {
			height += typingRowHeight
		}
		if replyVisible, typingVisible {
			height += UISpacing.tight
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
 can drag, with the width it settles on kept across launches.

 The pointer shape is `.pointerStyle`, not a `push()`/`pop()` pair on hover:
 the pair is unbalanced the moment the view disappears mid-hover -- collapse
 the member list from the menu with the pointer over the handle and the
 resize cursor stayed on the stack for the rest of the session. The handle is
 also reachable without the pointer: it takes focus, the arrow keys move it,
 and a double-click returns it to the ideal width. */
private struct MemberListResizeHandle: View {
	@Binding var width: CGFloat
	@State private var widthAtDragStart: CGFloat?
	@FocusState private var isFocused: Bool

	var body: some View {
		Divider()
			.frame(width: MainWindowConstants.memberListHandleWidth)
			.contentShape(Rectangle())
			/* The handle takes focus and the arrow keys resize from there, and
			 nothing on screen said so: a control that answers the keyboard has
			 to show when the keyboard is on it. A hairline in the accent colour
			 over the divider's own line, which is the whole control. */
			.overlay {
				if isFocused {
					Rectangle()
						.fill(Color.accentColor)
						.frame(width: 1)
						.accessibilityHidden(true)
				}
			}
			.pointerStyle(.columnResize)
			.gesture(
				DragGesture(minimumDistance: 1)
					.onChanged { value in
						let start = widthAtDragStart ?? width
						widthAtDragStart = start
						apply(start - value.translation.width, persist: false)
					}
					.onEnded { _ in
						widthAtDragStart = nil
						persistWidth()
					}
			)
			.onTapGesture(count: 2) {
				apply(MainWindowConstants.memberListIdealWidth, persist: true)
			}
			.focusable()
			.focused($isFocused)
			.onKeyPress(.leftArrow) {
				apply(width + MainWindowConstants.memberListKeyboardResizeStep, persist: true)
				return .handled
			}
			.onKeyPress(.rightArrow) {
				apply(width - MainWindowConstants.memberListKeyboardResizeStep, persist: true)
				return .handled
			}
			.accessibilityLabel(MainWindowStrings.Toolbar.memberListWidth)
			.accessibilityHint(MainWindowStrings.Toolbar.memberListWidthHint)
			.accessibilityAddTraits(.isButton)
			.help(MainWindowStrings.Toolbar.memberListWidth)
	}

	private func apply(_ candidate: CGFloat, persist: Bool) {
		width = MemberListWidthPolicy.clamped(candidate)
		if persist {
			persistWidth()
		}
	}

	private func persistWidth() {
		Preferences.MainWindow.memberListWidth.value = Double(width)
	}
}

/// The widths the member list is allowed to settle on. A drag, an arrow key
/// and the double-click reset all land here, so none of them can put a width
/// into the preference that the column cannot lay out.
enum MemberListWidthPolicy {
	static func clamped(_ candidate: CGFloat) -> CGFloat {
		min(
			MainWindowConstants.memberListMaximumWidth,
			max(MainWindowConstants.memberListMinimumWidth, candidate)
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
