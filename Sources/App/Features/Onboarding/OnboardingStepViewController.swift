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

public enum TDCOnboardingTextSize: UInt, CaseIterable, Sendable {
	case small = 0
	case medium
	case large
}

/// Why a step refused to commit. The message is shown to the user as-is.
public struct OnboardingStepError: Error {
	public let message: String

	public init(_ message: String) {
		self.message = message
	}
}

/// What the onboarding flow has collected so far. The steps share one instance
/// and each writes its own part of it, so it stays a reference type.
@MainActor
public final class OnboardingSettings {
	public var nickname = ""
	public var realName = ""
	public var alternateNickname: String?

	public var styleName = "Bubbles"
	public var textSize: TDCOnboardingTextSize = .medium
	public var appearance: TXPreferredAppearance = .inherited

	public var notifyOnHighlight = true
	public var notifyOnPrivateMessage = true
	public var playSounds = true

	public var clientConfig: ClientConfig?
	public var connectWhenFinished = true
	public var channelsToJoin: [String] = []

	public init() {}

	/// Exhaustive, so a new text size is a compile error rather than silently
	/// rendering at the medium size.
	public static func fontSize(for textSize: TDCOnboardingTextSize) -> CGFloat {
		switch textSize {
		case .small:
			11.0
		case .medium:
			13.0
		case .large:
			15.0
		}
	}

	public static func textSize(forFontSize fontSize: CGFloat) -> TDCOnboardingTextSize {
		if fontSize < 12.0 {
			return .small
		}

		if fontSize > 14.0 {
			return .large
		}

		return .medium
	}
}

// MARK: -

@objc(TDCOnboardingStepViewController)
@MainActor
open class OnboardingStepViewController: NSViewController {
	public var settings: OnboardingSettings

	@objc open var stepTitle: String {
		""
	}

	@objc open var stepSubtitle: String {
		""
	}

	@objc open var skippable: Bool {
		true
	}

	@objc open var preferredFirstResponder: NSView? {
		nil
	}

	public init(settings: OnboardingSettings) {
		self.settings = settings
		super.init(nibName: nil, bundle: nil)
	}

	@available(*, unavailable)
	public required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	@objc open func stepWillAppear() {}

	/// Writes the step's answers into `settings`. Throwing rejects the step and
	/// shows the thrown message; it used to be a `Bool` plus an `NSString`
	/// out-parameter.
	open func commit() throws {}

	@objc open func makeContentView() -> NSView {
		let view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 380))
		view.translatesAutoresizingMaskIntoConstraints = false
		return view
	}
}
