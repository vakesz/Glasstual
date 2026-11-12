// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/** The Server Properties windows: one per connection, resizable, not modal,
 listed in the Window menu under the connection's name and restored on the
 next launch.

 A window is keyed by the identifier of the connection it edits, so opening a
 connection's properties again brings its window forward rather than opening a
 second one. A restored window finds its connection by that identifier and
 closes itself when the connection no longer exists. */
struct ServerPropertiesScene: Scene {
	let windows: ServerPropertiesWindows

	var body: some Scene {
		WindowGroup(
			String(localized: .ServerProperties.serverPropertiesWindowGroupTitle),
			id: ApplicationSceneID.serverProperties,
			for: String.self
		) { windowID in
			ServerPropertiesWindowRoot(windowID: windowID.wrappedValue, windows: windows)
		}
		.defaultSize(width: 860, height: 620)
		.windowResizability(.contentMinSize)
	}
}

private struct ServerPropertiesWindowRoot: View {
	let windowID: String?
	let windows: ServerPropertiesWindows
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		if let windowID, let editor = windows.editor(forWindow: windowID) {
			ServerPropertiesWindowContent(editor: editor) { dismiss() }
				.onDisappear { windows.didClose(windowID) }
		} else {
			/* A restored window whose connection was deleted, or a new
			 connection's window from a previous launch: nothing to edit. */
			Color.clear
				.frame(width: 1, height: 1)
				.onAppear { dismiss() }
		}
	}
}

private struct ServerPropertiesWindowContent: View {
	@Bindable var editor: ServerPropertiesEditor
	let close: () -> Void
	/// The pane the window was left on, restored with it.
	@SceneStorage("ServerPropertiesPane") private var storedPane = ""

	var body: some View {
		ServerPropertiesView(model: editor.model, commands: editor)
			.frame(minWidth: 680, minHeight: 480)
			.navigationTitle(editor.windowTitle)
			.navigationSubtitle(editor.windowSubtitle)
			/* Unsaved edits keep the window open: they are saved or reverted,
			 never dropped by the close button. Quitting asks to review them. */
			.windowDismissBehavior(
				ServerPropertiesWindows.closingIsAllowed(for: editor.model) ? .automatic : .disabled
			)
			.sheet(item: presentedSheet) { presentation in
				MainWindowSheetHost(model: editor.sheetModel, presentation: presentation)
			}
			.alert(
				Text(.ServerProperties.thisConnectionsConfigurationHasChangedDo),
				isPresented: Binding(
					get: { editor.asksToReload },
					set: { isPresented in
						if isPresented == false, editor.asksToReload {
							editor.answerReloadQuestion(reload: false)
						}
					}
				)
			) {
				Button(.ServerProperties.keepEditingButton, role: .cancel) {
					editor.answerReloadQuestion(reload: false)
				}
				Button(.ServerProperties.reloadButton, role: .destructive) {
					editor.answerReloadQuestion(reload: true)
				}
			} message: {
				Text(.ServerProperties.youWillLooseUnsavedChangesIf)
			}
			.onAppear {
				if editor.model.templatePicker == nil,
				   let pane = ServerPropertiesSelection(storedName: storedPane),
				   pane.isListed(for: editor.model)
				{
					editor.model.selection = pane
				}
			}
			.onChange(of: editor.model.selection) { _, pane in
				storedPane = pane.storedName
			}
			.onChange(of: editor.closeRequested) { _, requested in
				if requested {
					close()
				}
			}
	}

	private var presentedSheet: Binding<MainWindowSheet?> {
		Binding(
			get: { editor.sheetModel.presentedSheet },
			set: { presentation in
				if presentation == nil {
					editor.sheetModel.dismissPresentedSheet()
				}
			}
		)
	}
}

/** The open Server Properties windows, one editor per window.

 The editor outlives a view rebuild and is what the window menu, `/serverconfig`
 and quitting all ask about; the window only draws it. */
@MainActor
final class ServerPropertiesWindows {
	private let scenes: ApplicationScenes
	private let save: @MainActor (ServerConfig, ServerSession?) -> Void
	private var editors = SceneSessions<String, ServerPropertiesEditor>()
	/// The windows in the order they were opened, so a review starts with the
	/// oldest edits.
	private var order: [String] = []

	init(scenes: ApplicationScenes = AppServices.scenes, save: @escaping @MainActor (ServerConfig, ServerSession?) -> Void) {
		self.scenes = scenes
		self.save = save
	}

	/// Whether the window may be closed without asking: nothing unsaved and
	/// nothing being saved.
	static func closingIsAllowed(for model: ServerPropertiesModel) -> Bool {
		model.hasUnsavedChanges == false && model.isSaving == false
	}

	/** The editor a window shows. A restored window has none yet, and gets one
	 for its connection as long as that connection still exists. */
	func editor(forWindow windowID: String) -> ServerPropertiesEditor? {
		if let editor = editors[windowID] {
			return editor
		}
		guard let session = AppServices.chatSession?.sessions.first(where: { $0.uniqueIdentifier == windowID }) else {
			return nil
		}
		return register(makeEditor(for: session))
	}

	/** Opens the properties of `session`, or a new connection's when it is nil.
	 A connection's window that is already open comes forward with its edits.
	 The address book is the People window's, so no pane is chosen here. */
	func open(for session: ServerSession?) {
		let editor = if let session, let existing = editors[session.uniqueIdentifier] {
			existing
		} else {
			register(makeEditor(for: session))
		}
		scenes.open(ApplicationSceneID.serverProperties, value: editor.windowID)
	}

	/// The window has gone, so the editor it was showing goes with it.
	func didClose(_ windowID: String) {
		order.removeAll { $0 == windowID }
		editors.close(windowID)?.windowDidClose()
	}

	/// Closes the window of a connection that is being removed. Its edits have
	/// nowhere left to be saved.
	func close(forSession sessionIdentifier: String) {
		guard editors[sessionIdentifier] != nil else { return }
		didClose(sessionIdentifier)
		scenes.dismiss(ApplicationSceneID.serverProperties, value: sessionIdentifier)
	}

	/// The windows holding edits nothing has saved, oldest first.
	var editorsWithUnsavedChanges: [ServerPropertiesEditor] {
		order.compactMap { editors[$0] }.filter(\.model.hasUnsavedChanges)
	}

	/// Brings a window forward, for the review quitting asks for.
	func bringForward(_ editor: ServerPropertiesEditor) {
		scenes.open(ApplicationSceneID.serverProperties, value: editor.windowID)
	}

	private func makeEditor(for session: ServerSession?) -> ServerPropertiesEditor {
		ServerPropertiesEditor(session: session, onSave: save)
	}

	private func register(_ editor: ServerPropertiesEditor) -> ServerPropertiesEditor {
		order.append(editor.windowID)
		return editors.open(editor.windowID) { editor }
	}
}
