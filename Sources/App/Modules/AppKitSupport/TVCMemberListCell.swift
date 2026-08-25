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

/* Avatars draw white initials, so the tint is kept dark and saturated
 enough for that to stay legible whatever the nickname colour style. */
private let avatarMaximumBrightness: CGFloat = 0.72
private let avatarMinimumSaturation: CGFloat = 0.45
private let avatarAwayAlpha: CGFloat = 0.5
private let statusImageWidth: CGFloat = 16.0

private final class MemberListCellDrawingContext: NSObject {
	var isSelected = false
	var isWindowActive = false
}

private func avatarColorFromHSL(hue: CGFloat, saturation: CGFloat, lightness: CGFloat) -> NSColor {
	/* HSL to HSB; both share the hue. */
	let brightness = lightness + (saturation * min(lightness, 1.0 - lightness))
	var hsbSaturation: CGFloat = 0.0

	if brightness > 0.0 {
		hsbSaturation = 2.0 * (1.0 - (lightness / brightness))
	}

	return NSColor(hue: hue, saturation: hsbSaturation, brightness: brightness, alpha: 1.0)
}

private func avatarColor(forNickname nickname: String) -> NSColor {
	let style = UserNicknameColorStyleGenerator.nicknameColorStyle(for: nickname)

	var color: NSColor?

	if style.hasPrefix("#") {
		color = NSColor(hexadecimalValue: style)
	} else if let match = style.wholeMatch(of: /hsl\((\d+),(\d+)%\,(\d+)%\)/) {
		color = avatarColorFromHSL(
			hue: CGFloat(Int(match.1) ?? 0) / 360.0,
			saturation: CGFloat(Int(match.2) ?? 0) / 100.0,
			lightness: CGFloat(Int(match.3) ?? 0) / 100.0
		)
	}

	guard var color else {
		return .systemGray
	}

	color = color.usingColorSpace(.sRGB) ?? color

	var h: CGFloat = 0
	var s: CGFloat = 0
	var b: CGFloat = 0
	color.getHue(&h, saturation: &s, brightness: &b, alpha: nil)

	b = min(b, avatarMaximumBrightness)
	s = max(s, avatarMinimumSaturation)

	return NSColor(hue: h, saturation: s, brightness: b, alpha: 1.0)
}

/** The first letter or digit of the nickname. Leading punctuation such
 as the brackets and underscores IRC users decorate nicknames with is
 skipped so that "[away]bob" still reads as "B". */
private func avatarInitial(forNickname nickname: String) -> String {
	var initial: String?

	nickname.enumerateSubstrings(
		in: nickname.startIndex ..< nickname.endIndex,
		options: .byComposedCharacterSequences
	) { substring, _, _, stop in
		guard let substring else {
			return
		}

		if substring.rangeOfCharacter(from: .alphanumerics) != nil {
			initial = substring
			stop = true
		}
	}

	if initial == nil {
		initial = String(nickname.prefix(1))
	}

	return initial?.uppercased() ?? ""
}

private func makeAvatarImage(initial: String, color: NSColor, size: CGFloat) -> NSImage {
	let font = NSFont.systemFont(ofSize: round(size * 0.48), weight: .semibold)
	let text = NSAttributedString(
		string: initial,
		attributes: [
			.font: font,
			.foregroundColor: NSColor.white,
		]
	)

	return NSImage(size: NSSize(width: size, height: size), flipped: false) { dstRect in
		color.setFill()
		NSBezierPath(ovalIn: dstRect).fill()

		/* Centre the glyph on the font's cap height. -drawAtPoint:
		 places the bottom of the line box at the point, and the
		 baseline sits |descender| above that. */
		let textSize = text.size()
		let textOrigin = NSPoint(
			x: dstRect.midX - (textSize.width / 2.0),
			y: dstRect.midY - (font.capHeight / 2.0) + font.descender
		)
		text.draw(at: textOrigin)
		return true
	}
}

private func userModeColor(defaultsKey: String) -> NSColor? {
	guard let color = TPCPreferencesUserDefaults.shared().color(forKey: defaultsKey),
	      color != .clear
	else {
		return nil
	}

	return color
}

private func color(for rank: IRCUserRank) -> NSColor? {
	switch rank {
	case .irCopByMode:
		userModeColor(defaultsKey: "User List Mode Badge Colors -> +y")
	case .channelOwner:
		userModeColor(defaultsKey: "User List Mode Badge Colors -> +q")
	case .superOperator:
		userModeColor(defaultsKey: "User List Mode Badge Colors -> +a")
	case .normalOperator:
		userModeColor(defaultsKey: "User List Mode Badge Colors -> +o")
	case .halfOperator:
		userModeColor(defaultsKey: "User List Mode Badge Colors -> +h")
	case .voiced:
		userModeColor(defaultsKey: "User List Mode Badge Colors -> +v")
	default:
		nil
	}
}

private func symbolName(for rank: IRCUserRank) -> String? {
	switch rank {
	case .irCopByMode:
		"checkmark.shield.fill"
	case .channelOwner:
		"crown.fill"
	case .superOperator:
		"star.fill"
	case .normalOperator:
		"shield.fill"
	case .halfOperator:
		"shield.lefthalf.filled"
	case .voiced:
		"mic.fill"
	default:
		nil
	}
}

@objc(TVCMemberListCell)
public final class MemberListCell: NSTableCellView {
	@IBOutlet private var cellTextField: NSTextField!
	@IBOutlet private var statusImageView: NSImageView!
	@IBOutlet private var statusImageWidthConstraint: NSLayoutConstraint!

	private static let avatarCache: NSCache<NSString, NSImage> = {
		let cache = NSCache<NSString, NSImage>()
		cache.countLimit = 4096
		return cache
	}()

	override public func awakeFromNib() {
		super.awakeFromNib()

		cellTextField.usesSingleLineMode = true
		cellTextField.maximumNumberOfLines = 1
		cellTextField.lineBreakMode = .byTruncatingTail
	}

	@objc(avatarImageForNickname:size:)
	public class func avatarImage(forNickname nickname: String, size: CGFloat) -> NSImage {
		let color = avatarColor(forNickname: nickname)
		let initial = avatarInitial(forNickname: nickname)

		/* The colour is part of the key because it follows the theme's
		 nickname colour style and the user's per-nickname overrides. */
		let key = String(format: "%.0f|%@|%@", size, color.hexadecimalValue, initial) as NSString

		if let image = avatarCache.object(forKey: key) {
			return image
		}

		let image = makeAvatarImage(initial: initial, color: color, size: size)
		avatarCache.setObject(image, forKey: key)
		return image
	}

	override public var wantsUpdateLayer: Bool {
		true
	}

	override public func updateLayer() {
		updateDrawing()
	}

	private func updateDrawing() {
		let drawingContext = drawingContext
		updateTextField(in: drawingContext)
		updateAvatar(in: drawingContext)
		updateStatus(in: drawingContext)
	}

	private func updateTextField(in _: MemberListCellDrawingContext) {
		guard let cellItem else {
			return
		}

		let nickname = cellItem.user.nickname
		cellTextField.attributedStringValue = attributedTextFieldValue()

		/* The accessibility description carries mode and away state as
		 well as the nickname, so it is rebuilt on every pass. */
		var accessibilityDescription = LocalizedKey("Accessibility[alq-6s]", nickname)
		accessibilityDescription += ", \(Self.privilegesDescription(for: cellItem))"

		if cellItem.user.isAway {
			accessibilityDescription += ", \(LocalizedKey("TVCMainWindow[jkr-ed]"))"
		}

		if cellItem.user.isBot {
			accessibilityDescription += ", \(LocalizedKey("TVCMainWindow[b0t-ac]"))"
		}

		if let account = cellItem.user.account, account.isEmpty == false {
			accessibilityDescription += ", \(LocalizedKey("TVCMainWindow[acc-in]", account))"
		}

		cellTextField.cell?.setAccessibilityValueDescription(accessibilityDescription)
		setAccessibilityLabel(accessibilityDescription)
	}

	@objc(privilegesDescriptionForUser:)
	public class func privilegesDescription(for cellItem: ChannelUser) -> String {
		var userRank = cellItem.rank

		if cellItem.user.isIRCop {
			userRank = .irCopByMode
		}

		if userRank == .irCopByMode {
			return LocalizedKey("TVCMainWindow[i8t-vb]")
		}

		if userRank == .channelOwner {
			return LocalizedKey("TVCMainWindow[p1z-sc]")
		}

		if userRank == .superOperator {
			return LocalizedKey("TVCMainWindow[som-zo]")
		}

		if userRank == .normalOperator {
			return LocalizedKey("TVCMainWindow[0kn-s5]")
		}

		if userRank == .halfOperator {
			return LocalizedKey("TVCMainWindow[0nn-te]")
		}

		if userRank == .voiced {
			return LocalizedKey("TVCMainWindow[ya1-sk]")
		}

		return LocalizedKey("TVCMainWindow[tjj-z2]")
	}

	private func attributedTextFieldValue() -> NSAttributedString {
		guard let cellItem else {
			return NSAttributedString()
		}

		let controlFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
		let controlColor: NSColor = cellItem.user.isAway ? .secondaryLabelColor : .labelColor

		let mutableStringValue = NSMutableAttributedString(
			string: cellItem.user.nickname,
			attributes: [
				.font: controlFont,
				.foregroundColor: controlColor,
			]
		)

		/* Bots (ISUPPORT BOT user mode, WHO flag, or RPL_WHOISBOT) get a
		 small caption after the nickname. */
		if cellItem.user.isBot {
			let captionFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
			let caption = "  \(LocalizedKey("TVCMainWindow[b0t-lb]"))"
			let captionValue = NSAttributedString(
				string: caption,
				attributes: [
					.font: captionFont,
					.foregroundColor: NSColor.secondaryLabelColor,
				]
			)
			mutableStringValue.append(captionValue)
		}

		return mutableStringValue
	}

	private func updateAvatar(in _: MemberListCellDrawingContext) {
		guard let cellItem, let imageView else {
			return
		}

		let size = imageView.bounds.height
		if size <= 0.0 {
			return // Not laid out yet
		}

		imageView.image = Self.avatarImage(forNickname: cellItem.user.nickname, size: size)
		imageView.alphaValue = cellItem.user.isAway ? avatarAwayAlpha : 1.0

		/* The initials repeat what the label already says. */
		imageView.cell?.setAccessibilityElement(false)
	}

	private func updateStatus(in drawingContext: MemberListCellDrawingContext) {
		guard let cellItem else {
			return
		}

		var userRank: IRCUserRank = .none

		if TPCPreferences.memberListSortFavorsServerStaff(), cellItem.user.isIRCop {
			userRank = .irCopByMode
		}

		if userRank == .none {
			userRank = cellItem.rank
		}

		guard let symbolName = symbolName(for: userRank) else {
			statusImageView.image = nil
			setStatusImageVisible(false)
			return
		}

		var symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
		symbol = symbol?.withSymbolConfiguration(
			NSImage.SymbolConfiguration(pointSize: 11.0, weight: .medium)
		)

		statusImageView.image = symbol
		setStatusImageVisible(true)

		/* The accent fill is only drawn while the window is active; an
		 inactive selection is grey and keeps the rank colour legible. */
		if drawingContext.isSelected, drawingContext.isWindowActive {
			statusImageView.contentTintColor = .alternateSelectedControlTextColor
		} else {
			statusImageView.contentTintColor = color(for: userRank) ?? .secondaryLabelColor
		}

		/* The rank is already part of the label's description. */
		statusImageView.cell?.setAccessibilityElement(false)
	}

	@objc(setStatusImageVisible:)
	public func setStatusImageVisible(_ visible: Bool) {
		statusImageView.isHidden = (visible == false)
		statusImageWidthConstraint.constant = visible ? statusImageWidth : 0.0
	}

	@objc
	public func drawWithExpansionFrame() {
		guard let memberList, let cellItem else {
			return
		}

		let userInfoPopover = memberList.memberListUserInfoPopover()
		let nickname = cellItem.user.nickname

		userInfoPopover.nicknameField.stringValue = nickname

		if let avatarImageView = userInfoPopover.avatarImageView {
			avatarImageView.image = Self.avatarImage(
				forNickname: nickname,
				size: avatarImageView.bounds.height
			)
			avatarImageView.cell?.setAccessibilityElement(false)
		}

		var hostmaskUsername = cellItem.user.username ?? ""
		if hostmaskUsername.isEmpty {
			hostmaskUsername = LocalizedKey("TVCMainWindow[d85-9n]")
		}
		userInfoPopover.usernameField.stringValue = hostmaskUsername

		let stripIRCFormatting = TPCPreferences.removeAllFormatting()

		var hostmaskAddress = cellItem.user.address ?? ""
		if hostmaskAddress.isEmpty {
			hostmaskAddress = LocalizedKey("TVCMainWindow[d85-9n]")
		}

		if stripIRCFormatting {
			userInfoPopover.addressField.stringValue = hostmaskAddress
		} else if let font = userInfoPopover.addressField.font,
		          let formatted = (hostmaskAddress as NSString).attributedString(
		          	withIRCFormatting: font,
		          	preferredFontColor: nil,
		          	honorFormattingPreference: false
		          )
		{
			userInfoPopover.addressField.attributedStringValue = formatted
		}

		var realName = cellItem.user.realName ?? ""
		if realName.isEmpty {
			realName = LocalizedKey("TVCMainWindow[d85-9n]")
		}

		if stripIRCFormatting {
			userInfoPopover.realNameField.stringValue = realName
		} else if let font = userInfoPopover.realNameField.font,
		          let formatted = (realName as NSString).attributedString(
		          	withIRCFormatting: font,
		          	preferredFontColor: nil,
		          	honorFormattingPreference: false
		          )
		{
			userInfoPopover.realNameField.attributedStringValue = formatted
		}

		if let account = cellItem.user.account, account.isEmpty == false {
			userInfoPopover.accountField.stringValue = account
		} else {
			userInfoPopover.accountField.stringValue = LocalizedKey("TVCMainWindow[acc-nl]")
		}

		if cellItem.user.isAway {
			userInfoPopover.awayStatusField.stringValue = LocalizedKey("TVCMainWindow[jkr-ed]")
		} else {
			userInfoPopover.awayStatusField.stringValue = LocalizedKey("TVCMainWindow[gi6-wf]")
		}

		var privileges = Self.privilegesDescription(for: cellItem)
		if cellItem.user.isBot {
			privileges = "\(privileges) (\(LocalizedKey("TVCMainWindow[b0t-lb]")))"
		}
		userInfoPopover.privilegesField.stringValue = privileges

		let rowIndex = memberList.row(for: self)
		let cellFrame = memberList.frameOfCell(atColumn: 0, row: rowIndex)

		/* Presenting the popover will steal focus. To workaround this,
		 we record the active first responder then set it back. */
		let window = window
		let activeFirstResponder = window?.firstResponder

		userInfoPopover.show(relativeTo: cellFrame, of: memberList, preferredEdge: .maxX)

		if let window, let activeFirstResponder {
			window.makeFirstResponder(activeFirstResponder)
		}
	}

	private var rowCell: MemberListRowCell? {
		superview as? MemberListRowCell
	}

	private var cellItem: ChannelUser? {
		objectValue as? ChannelUser
	}

	private var memberList: TVCMemberList? {
		rowCell?.memberList
	}

	private var drawingContext: MemberListCellDrawingContext {
		let drawingContext = MemberListCellDrawingContext()

		guard let memberList else {
			return drawingContext
		}

		let rowIndex = memberList.row(for: self)
		drawingContext.isSelected = memberList.isRowSelected(rowIndex)
		drawingContext.isWindowActive = mainWindow?.isActiveForDrawing ?? false
		return drawingContext
	}
}

// MARK: - Header Cell

@objc(TVCMemberListHeaderCell)
public final class MemberListHeaderCell: NSTableCellView {
	override public var objectValue: Any? {
		didSet {
			guard let section = objectValue as? TVCMemberListSection else {
				return
			}

			guard let textField else {
				return
			}

			let title = section.title.localizedUppercase
			textField.stringValue = title

			/* Source list section headers are small, bold and secondary; the
			 system does not restyle a custom cell view so it is done here. */
			textField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .bold)
			textField.textColor = .secondaryLabelColor
			setAccessibilityLabel(section.title)
		}
	}
}

// MARK: - Row View Cell

@objc(TVCMemberListRowCell)
public final class MemberListRowCell: NSTableRowView {
	@objc public private(set) weak var memberList: TVCMemberList?
	private weak var cachedChildCell: MemberListCell?

	@objc(initWithMemberList:)
	public init(memberList: TVCMemberList) {
		self.memberList = memberList
		super.init(frame: .zero)
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override public var isSelected: Bool {
		didSet {
			if isSelected == false, invalidatingBackgroundForSelection {
				return
			}

			setNeedsDisplayOnChild()
		}
	}

	private func setNeedsDisplayOnChild() {
		childCell?.needsDisplay = true
	}

	/** AppKit emphasizes a selection only while the window is key. Mail and
	 Finder keep the accent fill while a sheet or panel is key, so emphasis
	 follows main-window status instead. Both the getter and the background
	 style are overridden so that drawing and text colours agree regardless
	 of whether AppKit consults the accessor or the stored value. */
	override public var isEmphasized: Bool {
		get {
			guard let window else {
				return super.isEmphasized
			}

			return window.isMainWindow
		}
		set {
			if let window {
				super.isEmphasized = window.isMainWindow
			} else {
				super.isEmphasized = newValue
			}

			setNeedsDisplayOnChild()
		}
	}

	@objc
	public func refreshEmphasis() {
		isEmphasized = isEmphasized
	}

	override public var interiorBackgroundStyle: NSView.BackgroundStyle {
		if isSelected, isEmphasized {
			return .emphasized
		}

		return super.interiorBackgroundStyle
	}

	private var childCell: MemberListCell? {
		if cachedChildCell == nil {
			if numberOfColumns == 0 {
				return nil
			}

			cachedChildCell = view(atColumn: 0) as? MemberListCell
		}

		return cachedChildCell
	}
}
