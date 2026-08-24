/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2019 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit

@objc(TDCPreferencesUserStyleSheet)
@MainActor
public final class PreferencesUserStyleSheet: SheetBase {
	@IBOutlet private var rulesTextView: NSTextView!
	private var rulesChanged = false

	@objc(initWithWindow:)
	override public init(window: NSWindow?) {
		super.init(window: window)
		prepareInitialState()
	}

	private func prepareInitialState() {
		Bundle.main.loadNibNamed("TDCPreferencesUserStyleSheet", owner: self, topLevelObjects: nil)

		rulesTextView.font = NSFont.monospacedSystemFont(ofSize: 13.0, weight: .regular)
		rulesTextView.textContainerInset = NSSize(width: 1, height: 3)

		loadRules()
	}

	@objc public func start() {
		startSheet()
	}

	@objc public func textDidChange(_ notification: Notification) {
		if notification.object as AnyObject? === rulesTextView {
			rulesChanged = true
		}
	}

	private func loadRules() {
		var rules = TPCPreferences.themeUserStyleSheetRules()

		if rules == nil {
			rules = defaultRules
		}

		rulesTextView.string = rules ?? ""
		rulesChanged = false
	}

	private func saveRules() {
		var rules: String? = (rulesTextView.string as NSString).trim

		if rules?.isEmpty == true || rules == defaultRules {
			rules = nil
		}

		TPCPreferences.setThemeUserStyleSheetRules(rules)

		let selector = NSSelectorFromString("userStyleSheetRulesChanged:")
		if let delegate, delegate.responds(to: selector) {
			_ = delegate.perform(selector, with: self)
		}
	}

	@IBAction override public func ok(_: Any?) {
		if rulesChanged {
			saveRules()
		}

		super.ok(nil)
	}

	private var defaultRules: String {
		LocalizedKey("TDCPreferencesUserStyleSheet[q4s-3m]")
	}

	@objc public func windowWillClose(_: Notification) {
		let selector = NSSelectorFromString("userStyleSheetWillClose:")
		if let delegate, delegate.responds(to: selector) {
			_ = delegate.perform(selector, with: self)
		}
	}
}
