/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import CocoaExtensions
import SwiftUI
import UniformTypeIdentifiers

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
				prompt: Text(MainWindowStrings.InputBar.filterSidebar)
			)
			.searchFocused($isSearchFieldFocused)
			/* Transparent is not gone. VoiceOver walked the invisible sidebar and
			 transcript, and `disabled` does not reach the AppKit views inside,
			 so Tab still reached the message field. The window hides those
			 views and takes the keyboard back from them; see
			 `MainWindow.setConversationObscured(_:)`. */
			.disabled(loadingScreen.viewIsVisible)
			.accessibilityHidden(loadingScreen.viewIsVisible)
			.opacity(loadingScreen.viewIsVisible ? 0 : 1)
			.onChange(of: loadingScreen.viewIsVisible, initial: true) { _, isVisible in
				model.window?.setConversationObscured(isVisible)
			}

			if loadingScreen.viewIsVisible {
				MainWindowLoadingContent(model: loadingScreen)
					.transition(.opacity)
			}
		}
		.toolbar {
			/* No sidebar toggle is declared here: the split view contributes its
			 own where the system wants it, and re-declaring it only moved it. */
			ToolbarItem(placement: .primaryAction) {
				/* Declared whatever the selection is, and disabled where there
				 is no member list: a toolbar whose only button disappears on a
				 server row is a toolbar that changes shape as the reader moves
				 down the sidebar. The title says which way the press goes and
				 the symbol says which state the window is in, the way Mail's
				 sidebar toggle does: filled while the pane is showing. */
				Button(
					MainWindowStrings.Menu.memberList(isVisible: model.isMemberListVisible),
					systemImage: model.isMemberListVisible ? "sidebar.squares.trailing" : "sidebar.trailing"
				) {
					toggleMemberList()
				}
				.disabled(model.isMemberListAvailable == false)
				.help(MainWindowStrings.Menu.memberList(isVisible: model.isMemberListVisible))
			}
		}
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
		.preferencesTransfer(model.preferencesTransfer)
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
		.sheet(item: presentedSheet) { presentation in
			MainWindowSheetHost(model: model, presentation: presentation)
		}
	}

	private var serverListVisibility: Binding<NavigationSplitViewVisibility> {
		Binding(
			get: { model.isServerListVisible ? .doubleColumn : .detailOnly },
			set: { model.isServerListVisible = $0 != .detailOnly }
		)
	}

	/// Dismissing has to reach the session that raised the sheet, so the
	/// binding's write goes through the model rather than clearing the item.
	private var presentedSheet: Binding<PresentedSheet?> {
		Binding(
			get: { model.presentedSheet },
			set: { presentation in
				if presentation == nil {
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
					model.commands?.addServer(nil)
				}
				Button(MenuStrings.Server.addChannel, systemImage: "number") {
					model.commands?.addChannel(nil)
				}
			} label: {
				footerIcon("plus", titled: MainWindowStrings.InputBar.addServerOrChannel)
			} primaryAction: {
				model.commands?.addChannel(nil)
			}
			.sidebarFooterMenu()
			.help(MainWindowStrings.InputBar.addServerOrChannel)

			Spacer(minLength: UISpacing.regular)

			Menu {
				Button(MainWindowStrings.InputBar.markAllAsRead, systemImage: "checkmark.circle") {
					model.commands?.markAllAsRead(nil)
				}
				/* A mode is ticked while it is in force, which is what the
				 application menu and the Dock menu already do with it. Renaming
				 the item instead left one command with three names. */
				Toggle(MenuStrings.Notifications.muteNotifications, isOn: Binding(
					get: { model.areNotificationsDisabled },
					set: { _ in model.commands?.toggleMuteOnNotifications(nil) }
				))
				Divider()
				Button(MenuStrings.Window.addressBook, systemImage: "person.crop.circle") {
					model.commands?.showAddressBook(nil)
				}
				Button(MenuStrings.Window.fileTransfers, systemImage: "arrow.down.circle") {
					model.commands?.showFileTransfersWindow(nil)
				}
				Divider()
				Button(
					MainWindowStrings.Menu.memberList(isVisible: model.isMemberListVisible),
					systemImage: model.isMemberListVisible ? "sidebar.squares.trailing" : "sidebar.trailing"
				) {
					toggleMemberList()
				}
				.disabled(model.isMemberListAvailable == false)
				Button(MainWindowStrings.InputBar.settings, systemImage: "gear") {
					model.commands?.showPreferencesWindow(nil)
				}
			} label: {
				footerIcon("ellipsis.circle", titled: MainWindowStrings.InputBar.more)
			}
			.sidebarFooterMenu()
			.menuIndicator(.hidden)
			.help(MainWindowStrings.InputBar.more)
		}
		.padding(.horizontal, UISpacing.wide)
		.frame(height: MainWindowConstants.sidebarFooterHeight)
	}

	/// A bare `Image` carries no accessibility label, so VoiceOver announced
	/// the two always-visible sidebar controls as "plus, menu" and nothing at
	/// all. A `Label` keeps the name for assistive technology while drawing
	/// only the symbol.
	private func footerIcon(_ systemName: String, titled title: String) -> some View {
		Label(title, systemImage: systemName)
			.labelStyle(.iconOnly)
			.font(.callout.weight(.medium))
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
				TranscriptViewRepresentable(
					logView: model.transcript,
					inputField: inputContentView,
					accessoryHeight: MainWindowInputBarLayout.accessoryHeight(
						for: inputContentView.textView.accessoryModel
					),
					isObscured: model.isConversationObscured
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
					.frame(
						minHeight: MainWindowInputBarLayout.minimumHostHeight,
						idealHeight: MainWindowInputBarLayout.idealHostHeight
					)
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
	 capsule takes the system's own focus-ring colour while the field holds the
	 keyboard -- which tracks both the accent setting and Increase Contrast --
	 drawn thicker where the system asks for increased contrast. */
	private var focusRing: some View {
		Capsule()
			.strokeBorder(
				Color(nsColor: .keyboardFocusIndicatorColor),
				lineWidth: contrast == .increased
					? MainWindowConstants.focusRingWidthIncreasedContrast
					: MainWindowConstants.focusRingWidth
			)
			.opacity(inputContentView.textView.focusModel.isFocused ? 1 : 0)
			.animation(
				reduceMotion ? nil : .easeOut(duration: 0.12),
				value: inputContentView.textView.focusModel.isFocused
			)
			.accessibilityHidden(true)
	}

	private var conversationBackground: Color {
		_ = model.appearanceRevision
		return Color(nsColor: AppServices.theme.backgroundColor)
	}

	/** A pane sweeping across the window is exactly the motion Reduce Motion
	 asks an interface to drop, so the column simply appears instead. The state
	 change is the view's to animate: the model only records it. */
	private func toggleMemberList() {
		withAnimation(ReduceMotion.animation(.default)) {
			model.toggleMemberList()
		}
	}

	private func redirectTyping(_ text: String) {
		let textView = inputContentView.textView
		textView.focus()
		textView.insertText(text, replacementRange: textView.selectedRange())
	}
}

private struct MainWindowSheetHost: View {
	let model: MainWindowPresentationModel
	@Bindable var presentation: PresentedSheet

	var body: some View {
		presentation.content
			/* Every hosted sheet is sized by its own content: `.fitted` asks for
			 the content's ideal size and leaves the user free to drag the sheet
			 anywhere between the content's minimum and maximum. */
			.presentationSizing(.fitted)
			.sheet(item: child) { nested in
				MainWindowSheetHost(model: model, presentation: nested)
			}
	}

	private var child: Binding<PresentedSheet?> {
		Binding(
			get: { presentation.child },
			set: { nested in
				if nested == nil {
					model.dismiss(presentation.child)
				}
			}
		)
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

private extension View {
	/// A footer control: a bare icon as the label, with the accessory bar's
	/// hover and pressed treatment so it answers the pointer the way the rows
	/// above it do. The label style is left alone so the menu's own items keep
	/// their titles.
	func sidebarFooterMenu() -> some View {
		menuStyle(.button)
			.buttonStyle(.accessoryBar)
	}
}
