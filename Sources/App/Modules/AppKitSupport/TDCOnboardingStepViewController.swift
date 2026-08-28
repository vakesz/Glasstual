/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit

@objc public enum TDCOnboardingTextSize: UInt {
	case small = 0
	case medium
	case large
}

@objc(TDCOnboardingSettings)
public final class OnboardingSettings: NSObject {
	@objc public var nickname = ""
	@objc public var realName = ""
	@objc public var alternateNickname: String?

	@objc public var styleName = "Bubbles"
	@objc public var textSize: TDCOnboardingTextSize = .medium
	@objc public var appearance: TXPreferredAppearance = .inherited

	@objc public var notifyOnHighlight = true
	@objc public var notifyOnPrivateMessage = true
	@objc public var playSounds = true

	public var clientConfig: ClientConfig?
	@objc public var connectWhenFinished = true
	@objc public var channelsToJoin: [String] = []

	@objc(fontSizeForTextSize:)
	public static func fontSize(for textSize: TDCOnboardingTextSize) -> CGFloat {
		switch textSize {
		case .small:
			11.0
		case .large:
			15.0
		default:
			13.0
		}
	}

	@objc(textSizeForFontSize:)
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
	@objc public var settings: OnboardingSettings

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

	@objc(initWithSettings:)
	public init(settings: OnboardingSettings) {
		self.settings = settings
		super.init(nibName: nil, bundle: nil)
	}

	@available(*, unavailable)
	public required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	@objc open func stepWillAppear() {}

	@objc(commitWithError:)
	open func commit(errorDescription _: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
		true
	}

	@objc open func makeContentView() -> NSView {
		let view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 380))
		view.translatesAutoresizingMaskIntoConstraints = false
		return view
	}
}
