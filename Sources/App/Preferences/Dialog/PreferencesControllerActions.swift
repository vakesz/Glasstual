/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import AppKit
import os

private let preferencesActionsLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "PreferencesActions"
)

/** Everything a pane asks the shell to do, because it needs a window: panels,
 sheets, alerts and the permission prompt for inline media. */
extension PreferencesController: PreferencesPaneActionHandler {
	// MARK: - Style

	func selectTheme(_ choice: PreferencesThemeChoice) {
		guard let newTheme = TPCThemeController.buildFilename(
			choice.themeName,
			for: choice.storageLocation
		) else { return }
		guard TextualPreferences.themeName() != newTheme else { return }
		TextualPreferences.setThemeName(newTheme)
		model.selectedTheme = choice
		beginThemeSelectionReload()
		TextualPreferences.performReloadAction([.style, .textDirection])
	}

	func browseStyleFiles() {
		guard SharedApplication.sharedThemeController().isBundledTheme else {
			openPathToTheme()
			return
		}
		TDCAlert.alertSheet(
			with: window,
			body: PreferencesStrings.styleModificationBody,
			title: PreferencesStrings.styleModificationTitle,
			defaultButton: PreferencesStrings.viewStyleFilesButtonTitle,
			alternateButton: PreferencesStrings.editStyleButtonTitle,
			otherButton: PreferencesStrings.createStyleCopyButtonTitle
		) { [weak self] outcome in
			self?.openPathToThemesCallback(outcome.response)
		}
	}

	private func openPathToThemesCallback(_ returnCode: TDCAlertResponse) {
		switch returnCode {
		case .default:
			openPathToTheme()
		case .alternate:
			editUserStyleSheetRules()
		case .other:
			SharedApplication.sharedThemeController().copyActiveTheme(
				to: .custom,
				reloadOnCopy: true,
				openOnCopy: true
			)
		}
	}

	private func openPathToTheme() {
		NSWorkspace.shared.open(SharedApplication.sharedThemeController().originalURL)
	}

	func editUserStyleSheetRules() {
		let sheet = PreferencesUserStyleSheet(window: window)
		sheet.delegate = self
		sheet.start()
		userStyleSheet = sheet
	}

	public func userStyleSheetRulesChanged(_: PreferencesUserStyleSheet) {
		TextualPreferences.performReloadAction([.style, .textDirection])
	}

	public func userStyleSheetWillClose(_: PreferencesUserStyleSheet) {
		userStyleSheet = nil
	}

	// MARK: - Font panel

	func selectChannelViewFont() {
		guard let currentFont = TextualPreferences.themeChannelViewFont() else { return }
		NSFontManager.shared.setSelectedFont(currentFont, isMultiple: false)
		NSFontManager.shared.orderFrontFontPanel(self)
		if fontPanelIsOwned == false {
			previousFontManagerAction = NSFontManager.shared.action
			fontPanelIsOwned = true
		}
		NSFontManager.shared.action = #selector(changeChannelViewFont(_:))
	}

	@objc private func changeChannelViewFont(_ sender: NSFontManager) {
		guard let currentFont = TextualPreferences.themeChannelViewFont() else { return }
		let newFont = sender.convert(currentFont)
		TextualPreferences.setThemeChannelViewFontName(newFont.fontName)
		TextualPreferences.setThemeChannelViewFontSize(newFont.pointSize)
		model.refreshChannelViewFont()
		TextualPreferences.performReloadAction([.style, .textDirection])
	}

	func releaseFontPanel() {
		guard fontPanelIsOwned else { return }
		fontPanelIsOwned = false
		if let previousFontManagerAction {
			NSFontManager.shared.action = previousFontManagerAction
		}
		previousFontManagerAction = nil
		if NSFontPanel.sharedFontPanelExists {
			NSFontPanel.shared.orderOut(self)
		}
	}

	// MARK: - Folders

	func selectTranscriptFolder() {
		chooseFolder { [weak self] bookmark in
			self?.setTranscriptFolder(bookmark)
		}
	}

	func clearTranscriptFolder() {
		setTranscriptFolder(nil)
	}

	private func setTranscriptFolder(_ bookmark: Data?) {
		PathInfo.setTranscriptFolderURL(bookmark)
		TextualPreferences.performReloadAction(.logTranscripts)
		model.refreshFolders()
	}

	func selectDownloadFolder() {
		chooseFolder { [weak self] bookmark in
			SharedApplication.sharedFileTransferDialog().setDownloadDestinationURL(bookmark)
			self?.model.refreshFolders()
		}
	}

	func clearDownloadFolder() {
		SharedApplication.sharedFileTransferDialog().setDownloadDestinationURL(nil)
		model.refreshFolders()
	}

	private func chooseFolder(completion: @escaping (Data) -> Void) {
		let panel = NSOpenPanel()
		panel.allowsMultipleSelection = false
		panel.canChooseDirectories = true
		panel.canChooseFiles = false
		panel.canCreateDirectories = true
		panel.resolvesAliases = true
		panel.prompt = PromptStrings.Action.select
		panel.beginSheetModal(for: window) { response in
			guard response == .OK, let path = panel.url else { return }
			do {
				let bookmark = try path.bookmarkData(
					options: .withSecurityScope,
					includingResourceValuesForKeys: nil,
					relativeTo: nil
				)
				completion(bookmark)
			} catch {
				preferencesActionsLogger.error(
					"""
					Failed to create a security-scoped bookmark for the chosen folder: \
					\(error.localizedDescription, privacy: .public)
					"""
				)
			}
		}
	}

	func openCustomAddOnsFolder() {
		if let scriptsURL = PathInfo.customScriptsURL,
		   FileManager.default.fileExists(atPath: scriptsURL.path)
		{
			NSWorkspace.shared.open(scriptsURL)
		} else if let applicationScriptsURL = PathInfo.userApplicationScriptsURL {
			/* A sandboxed app may read its Application Scripts directory but may
			 not create it. Finder gives the user the right place to create the
			 bundle-ID folder named in the pane's installation note. */
			NSWorkspace.shared.open(applicationScriptsURL)
		}
	}

	// MARK: - Inline media

	func setInlineMediaEnabled(_ enabled: Bool) {
		guard enabled else {
			TextualPreferences.setShowInlineMedia(false)
			model.preferences.invalidate()
			TextualPreferences.performReloadAction([.style, .textDirection])
			return
		}
		LogControllerInlineMediaService.askPermissionToEnableInlineMedia { [weak self] granted in
			Task { @MainActor [weak self] in
				guard let self, granted else { return }
				TextualPreferences.setShowInlineMedia(true)
				model.preferences.invalidate()
				TextualPreferences.performReloadAction([.style, .textDirection])
			}
		}
	}
}
