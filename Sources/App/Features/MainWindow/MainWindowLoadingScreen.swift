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

import AppKit

@objc(TVCMainWindowLoadingScreenView)
@MainActor
public final class MainWindowLoadingScreenView: NSVisualEffectView {
	@IBOutlet private var visibleView: NSView?
	@IBOutlet private var welcomeAddServerView: NSView!
	@IBOutlet private var welcomeAddServerViewContinueButton: NSButton!
	@IBOutlet private var progressView: NSView!
	@IBOutlet private var progressViewDescriptionTextField: NSTextField!
	@IBOutlet private var progressViewIndicator: NSProgressIndicator!

	@objc public var viewIsVisible: Bool {
		isHidden == false
	}

	private var hasConfigured = false

	/// Nib-time configuration, run by the main window once its nib has finished
	/// decoding.
	///
	/// It was `awakeFromNib`, which is nonisolated. `viewDidMoveToWindow` is
	/// isolated but too early: AppKit installs the content view before it
	/// connects the outlets, so the welcome view below would still be nil.
	public func configure() {
		guard hasConfigured == false else {
			return
		}

		hasConfigured = true
		applyWelcomeViewAppearance()
	}

	private func applyWelcomeViewAppearance() {
		welcomeAddServerViewContinueButton.keyEquivalent = "\r"

		for subview in welcomeAddServerView.subviews {
			guard let textField = subview as? NSTextField else {
				continue
			}

			if textField.font?.pointSize ?? 0 > 20.0 {
				textField.font = NSFont.preferredFont(forTextStyle: .largeTitle, options: [:])
			} else {
				textField.font = NSFont.preferredFont(forTextStyle: .body, options: [:])
				textField.textColor = .secondaryLabelColor
			}
		}
	}

	@objc public func showWelcomeAddServerView() {
		displayView(welcomeAddServerView)
	}

	@objc(showProgressViewWithReason:)
	public func showProgressView(withReason progressReason: String) {
		displayView(progressView)
		setProgressViewReason(progressReason)
		progressViewIndicator.startAnimation(nil)
	}

	@objc(setProgressViewReason:)
	public func setProgressViewReason(_ progressReason: String) {
		progressViewDescriptionTextField.stringValue = progressReason
	}

	@objc public func hide() {
		hideAnimated(false)
	}

	@objc public func hideAnimated() {
		hideAnimated(true)
	}

	@objc(hideAnimated:)
	public func hideAnimated(_ animated: Bool) {
		guard let visibleView else {
			return
		}

		hideView(visibleView, animate: animated)
	}

	private func displayView(_ view: NSView) {
		if let visibleView {
			visibleView.removeFromSuperview()
		}

		visibleView = view

		disableBackgroundControlsStepOne()
		addSubview(view)

		let constraints = [
			NSLayoutConstraint(
				item: view,
				attribute: .centerX,
				relatedBy: .equal,
				toItem: self,
				attribute: .centerX,
				multiplier: 1.0,
				constant: 0.0
			),
			NSLayoutConstraint(
				item: view,
				attribute: .centerY,
				relatedBy: .equal,
				toItem: self,
				attribute: .centerY,
				multiplier: 1.0,
				constant: 0.0
			),
			NSLayoutConstraint(
				item: view,
				attribute: .left,
				relatedBy: .greaterThanOrEqual,
				toItem: self,
				attribute: .left,
				multiplier: 1.0,
				constant: 0.0
			),
			NSLayoutConstraint(
				item: view,
				attribute: .top,
				relatedBy: .greaterThanOrEqual,
				toItem: self,
				attribute: .top,
				multiplier: 1.0,
				constant: 0.0
			),
		]

		addConstraints(constraints)

		alphaValue = 1.0
		isHidden = false
		displayIfNeeded()
		disableBackgroundControlsStepTwo()
	}

	private func hideView(_ view: NSView, animate: Bool) {
		enableBackgroundControlsStepOne()

		let phaseTwoBlock: @MainActor @Sendable () -> Void = { [weak self] in
			guard let self else {
				return
			}

			view.removeFromSuperview()

			if visibleView === view {
				visibleView = nil
				isHidden = true
				enableBackgroundControlsStepTwo()
			}
		}

		if animate == false {
			alphaValue = 0.0
			phaseTwoBlock()
			return
		}

		/* `NSAnimationContext`'s completion handler is nonisolated, so running
		 phase two from inside it took a runtime assumption. Resuming a
		 continuation is all the handler does now — the work after the `await`
		 is back on the main actor by declaration. */
		Task { @MainActor in
			await withCheckedContinuation { continuation in
				NSAnimationContext.runAnimationGroup { context in
					context.duration = 1.0
					self.animator().alphaValue = 0.0
				} completionHandler: {
					continuation.resume()
				}
			}

			phaseTwoBlock()
		}
	}

	private func disableBackgroundControlsStepOne() {
		mainWindow?.contentSplitViewController.view.isHidden = true
	}

	private func disableBackgroundControlsStepTwo() {
		guard let textField = mainWindow?.inputTextField as? TextViewWithIRCFormatter else {
			return
		}

		textField.isEditable = false
		textField.isSelectable = false
	}

	private func enableBackgroundControlsStepOne() {
		mainWindow?.contentSplitViewController.view.isHidden = false
	}

	private func enableBackgroundControlsStepTwo() {
		guard let textField = mainWindow?.inputTextField as? TextViewWithIRCFormatter else {
			return
		}

		textField.isEditable = true
		textField.isSelectable = true
	}
}
