/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
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

#import "NSStringHelper.h"
#import "NSColorHelper.h"
#import "NSViewHelperPrivate.h"
#import "TPCPreferencesUserDefaults.h"
#import "TLOLocalization.h"
#import "TPCPreferencesLocal.h"
#import "IRCChannelUser.h"
#import "IRCUser.h"
#import "IRCUserNicknameColorStyleGeneratorPrivate.h"
#import "TVCMainWindow.h"
#import "TVCMemberListPrivate.h"
#import "TVCMemberListUserInfoPopoverPrivate.h"
#import "TVCMemberListCellPrivate.h"

NS_ASSUME_NONNULL_BEGIN

/* Avatars draw white initials, so the tint is kept dark and saturated
 enough for that to stay legible whatever the nickname colour style. */
static const CGFloat TVCMemberListAvatarMaximumBrightness = 0.72;
static const CGFloat TVCMemberListAvatarMinimumSaturation = 0.45;

static const CGFloat TVCMemberListAvatarAwayAlpha = 0.5;

@class TVCMemberListCellDrawingContext;

@interface TVCMemberListRowCell ()
@property(nonatomic, weak) TVCMemberList *memberList;
@property(nonatomic, weak) TVCMemberListCell *childCell;
@end

@interface TVCMemberListCell ()
@property(nonatomic, weak) IBOutlet NSTextField *cellTextField;
@property(nonatomic, weak) IBOutlet NSImageView *statusImageView;
@property(readonly, copy) TVCMemberListCellDrawingContext *drawingContext;
@property(readonly) TVCMemberList *memberList;
@property(readonly) TVCMemberListRowCell *rowCell;
@property(readonly) IRCChannelUser *cellItem;
@property(readonly) NSInteger rowIndex;
@end

@interface TVCMemberListCellDrawingContext : NSObject
@property(nonatomic, assign) BOOL isSelected;
@property(nonatomic, assign) BOOL isWindowActive;
@end

#pragma mark -
#pragma mark Avatar

static NSColor *TVCMemberListAvatarColorFromHSL(CGFloat hue, CGFloat saturation, CGFloat lightness)
{
	/* HSL to HSB; both share the hue. */
	CGFloat brightness = (lightness + (saturation * MIN(lightness, (1.0 - lightness))));

	CGFloat hsbSaturation = 0.0;

	if (brightness > 0.0) {
		hsbSaturation = (2.0 * (1.0 - (lightness / brightness)));
	}

	return [NSColor colorWithHue:hue saturation:hsbSaturation brightness:brightness alpha:1.0];
}

static NSColor *TVCMemberListAvatarColorForNickname(NSString *nickname)
{
	NSString *style = [IRCUserNicknameColorStyleGenerator nicknameColorStyleForString:nickname];

	NSColor *color = nil;

	int hue = 0;
	int saturation = 0;
	int lightness = 0;

	if ([style hasPrefix:@"#"]) {
		color = [NSColor colorWithHexadecimalValue:style];
	} else if (sscanf(style.UTF8String, "hsl(%d,%d%%,%d%%)", &hue, &saturation, &lightness) == 3) {
		color = TVCMemberListAvatarColorFromHSL((hue / 360.0), (saturation / 100.0), (lightness / 100.0));
	}

	if (color == nil) {
		return [NSColor systemGrayColor];
	}

	color = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];

	CGFloat h = 0.0;
	CGFloat s = 0.0;
	CGFloat b = 0.0;

	[color getHue:&h saturation:&s brightness:&b alpha:NULL];

	b = MIN(b, TVCMemberListAvatarMaximumBrightness);
	s = MAX(s, TVCMemberListAvatarMinimumSaturation);

	return [NSColor colorWithHue:h saturation:s brightness:b alpha:1.0];
}

/* The first letter or digit of the nickname. Leading punctuation such
 as the brackets and underscores IRC users decorate nicknames with is
 skipped so that "[away]bob" still reads as "B". */
static NSString *TVCMemberListAvatarInitialForNickname(NSString *nickname)
{
	__block NSString *initial = nil;

	[nickname
		enumerateSubstringsInRange:nickname.range
						   options:NSStringEnumerationByComposedCharacterSequences
						usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
							if ([substring rangeOfCharacterFromSet:[NSCharacterSet alphanumericCharacterSet]]
									.location != NSNotFound) {
								initial = substring;

								*stop = YES;
							}
						}];

	if (initial == nil) {
		initial = [nickname substringToIndex:MIN(nickname.length, (NSUInteger)1)];
	}

	return initial.uppercaseString;
}

static NSImage *TVCMemberListAvatarImage(NSString *initial, NSColor *color, CGFloat size)
{
	NSFont *font = [NSFont systemFontOfSize:round(size * 0.48) weight:NSFontWeightSemibold];

	NSAttributedString *text =
		[NSAttributedString attributedStringWithString:initial
											attributes:@{
												NSFontAttributeName : font,
												NSForegroundColorAttributeName : [NSColor whiteColor]
											}];

	return [NSImage imageWithSize:NSMakeSize(size, size)
						  flipped:NO
				   drawingHandler:^BOOL(NSRect dstRect) {
					   [color setFill];

					   [[NSBezierPath bezierPathWithOvalInRect:dstRect] fill];

					   /* Centre the glyph on the font's cap height. -drawAtPoint:
						places the bottom of the line box at the point, and the
						baseline sits |descender| above that. */
					   NSSize textSize = text.size;

					   NSPoint textOrigin = NSMakePoint((NSMidX(dstRect) - (textSize.width / 2.0)),
														(NSMidY(dstRect) - (font.capHeight / 2.0) + font.descender));

					   [text drawAtPoint:textOrigin];

					   return YES;
				   }];
}

@implementation TVCMemberListCell

+ (NSImage *)avatarImageForNickname:(NSString *)nickname size:(CGFloat)size
{
	NSParameterAssert(nickname != nil);

	static NSCache<NSString *, NSImage *> *cache = nil;

	static dispatch_once_t onceToken;

	dispatch_once(&onceToken, ^{
		cache = [NSCache new];

		cache.countLimit = 4096;
	});

	NSColor *color = TVCMemberListAvatarColorForNickname(nickname);

	NSString *initial = TVCMemberListAvatarInitialForNickname(nickname);

	/* The colour is part of the key because it follows the theme's
	 nickname colour style and the user's per-nickname overrides. */
	NSString *key = [NSString stringWithFormat:@"%.0f|%@|%@", size, color.hexadecimalValue, initial];

	NSImage *image = [cache objectForKey:key];

	if (image) {
		return image;
	}

	image = TVCMemberListAvatarImage(initial, color, size);

	[cache setObject:image forKey:key];

	return image;
}

#pragma mark -
#pragma mark Drawing

- (BOOL)wantsUpdateLayer
{
	return YES;
}

- (NSViewLayerContentsRedrawPolicy)layerContentsRedrawPolicy
{
	return NSViewLayerContentsRedrawOnSetNeedsDisplay;
}

- (void)updateLayer
{
	[self updateDrawing];
}

- (void)updateDrawing
{
	TVCMemberListCellDrawingContext *drawingContext = self.drawingContext;

	[self updateTextFieldInContext:drawingContext];

	[self updateAvatarInContext:drawingContext];

	[self updateStatusInContext:drawingContext];
}

- (void)updateTextFieldInContext:(TVCMemberListCellDrawingContext *)drawingContext
{
	NSParameterAssert(drawingContext != nil);

	IRCChannelUser *cellItem = self.cellItem;

	NSString *nickname = cellItem.user.nickname;

	self.cellTextField.attributedStringValue = [self attributedTextFieldValue];

	/* The accessibility description carries mode and away state as
	 well as the nickname, so it is rebuilt on every pass. */
	NSString *accessibilityDescription = TXTLS(@"Accessibility[alq-6s]", nickname);

	accessibilityDescription =
		[accessibilityDescription stringByAppendingFormat:@", %@", [self.class privilegesDescriptionForUser:cellItem]];

	if (cellItem.user.isAway) {
		accessibilityDescription =
			[accessibilityDescription stringByAppendingFormat:@", %@", TXTLS(@"TVCMainWindow[jkr-ed]")];
	}

	if (cellItem.user.isBot) {
		accessibilityDescription =
			[accessibilityDescription stringByAppendingFormat:@", %@", TXTLS(@"TVCMainWindow[b0t-ac]")];
	}

	if (cellItem.user.account.length > 0) {
		accessibilityDescription = [accessibilityDescription
			stringByAppendingFormat:@", %@", TXTLS(@"TVCMainWindow[acc-in]", cellItem.user.account)];
	}

	NSTextFieldCell *textFieldCell = self.cellTextField.cell;

	textFieldCell.accessibilityValueDescription = accessibilityDescription;

	self.accessibilityLabel = accessibilityDescription;
}

+ (NSString *)privilegesDescriptionForUser:(IRCChannelUser *)cellItem
{
	NSParameterAssert(cellItem != nil);

	IRCUserRank userRank = cellItem.rank;

	if (cellItem.user.isIRCop) {
		userRank = IRCUserRankIRCopByMode;
	}

	if (userRank == IRCUserRankIRCopByMode) {
		return TXTLS(@"TVCMainWindow[i8t-vb]");
	} else if (userRank == IRCUserRankChannelOwner) {
		return TXTLS(@"TVCMainWindow[p1z-sc]");
	} else if (userRank == IRCUserRankSuperOperator) {
		return TXTLS(@"TVCMainWindow[som-zo]");
	} else if (userRank == IRCUserRankNormalOperator) {
		return TXTLS(@"TVCMainWindow[0kn-s5]");
	} else if (userRank == IRCUserRankHalfOperator) {
		return TXTLS(@"TVCMainWindow[0nn-te]");
	} else if (userRank == IRCUserRankVoiced) {
		return TXTLS(@"TVCMainWindow[ya1-sk]");
	}

	return TXTLS(@"TVCMainWindow[tjj-z2]");
}

- (NSAttributedString *)attributedTextFieldValue
{
	IRCChannelUser *cellItem = self.cellItem;

	NSFont *controlFont = [NSFont systemFontOfSize:NSFont.systemFontSize];

	NSColor *controlColor = (cellItem.user.isAway ? [NSColor secondaryLabelColor] : [NSColor labelColor]);

	NSMutableAttributedString *mutableStringValue = [[NSMutableAttributedString alloc]
		initWithString:cellItem.user.nickname
			attributes:@{NSFontAttributeName : controlFont, NSForegroundColorAttributeName : controlColor}];

	/* Bots (ISUPPORT BOT user mode, WHO flag, or RPL_WHOISBOT) get a
	 small caption after the nickname. */
	if (cellItem.user.isBot) {
		NSFont *captionFont = [NSFont systemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightMedium];

		NSString *caption = [NSString stringWithFormat:@"  %@", TXTLS(@"TVCMainWindow[b0t-lb]")];

		NSAttributedString *captionValue =
			[[NSAttributedString alloc] initWithString:caption
											attributes:@{
												NSFontAttributeName : captionFont,
												NSForegroundColorAttributeName : [NSColor secondaryLabelColor]
											}];

		[mutableStringValue appendAttributedString:captionValue];
	}

	return mutableStringValue;
}

- (void)updateAvatarInContext:(TVCMemberListCellDrawingContext *)drawingContext
{
	NSParameterAssert(drawingContext != nil);

	IRCChannelUser *cellItem = self.cellItem;

	NSImageView *imageView = self.imageView;

	CGFloat size = NSHeight(imageView.bounds);

	if (size <= 0.0) {
		return; // Not laid out yet
	}

	imageView.image = [self.class avatarImageForNickname:cellItem.user.nickname size:size];

	imageView.alphaValue = (cellItem.user.isAway ? TVCMemberListAvatarAwayAlpha : 1.0);

	/* The initials repeat what the label already says. */
	imageView.cell.accessibilityElement = NO;
}

#pragma mark -
#pragma mark Status

/* Mode colours are user configurable; everything that is not
 configurable comes from the system so the symbol tracks the user's
 accent colour and appearance without a private colour table. */
static NSColor *_Nullable TVCMemberListCellUserModeColor(NSString *defaultsKey)
{
	NSColor *color = [RZUserDefaults() colorForKey:defaultsKey];

	if (color == nil || [color isEqual:[NSColor clearColor]]) {
		return nil;
	}

	return color;
}

static NSColor *_Nullable TVCMemberListCellColorForRank(IRCUserRank userRank)
{
	switch (userRank) {
	case IRCUserRankIRCopByMode:
		return TVCMemberListCellUserModeColor(@"User List Mode Badge Colors -> +y");
	case IRCUserRankChannelOwner:
		return TVCMemberListCellUserModeColor(@"User List Mode Badge Colors -> +q");
	case IRCUserRankSuperOperator:
		return TVCMemberListCellUserModeColor(@"User List Mode Badge Colors -> +a");
	case IRCUserRankNormalOperator:
		return TVCMemberListCellUserModeColor(@"User List Mode Badge Colors -> +o");
	case IRCUserRankHalfOperator:
		return TVCMemberListCellUserModeColor(@"User List Mode Badge Colors -> +h");
	case IRCUserRankVoiced:
		return TVCMemberListCellUserModeColor(@"User List Mode Badge Colors -> +v");
	default:
		return nil;
	}
}

static NSString *_Nullable TVCMemberListCellSymbolNameForRank(IRCUserRank userRank)
{
	switch (userRank) {
	case IRCUserRankIRCopByMode:
		return @"checkmark.shield.fill";
	case IRCUserRankChannelOwner:
		return @"crown.fill";
	case IRCUserRankSuperOperator:
		return @"star.fill";
	case IRCUserRankNormalOperator:
		return @"shield.fill";
	case IRCUserRankHalfOperator:
		return @"shield.lefthalf.filled";
	case IRCUserRankVoiced:
		return @"mic.fill";
	default:
		return nil;
	}
}

- (void)updateStatusInContext:(TVCMemberListCellDrawingContext *)drawingContext
{
	NSParameterAssert(drawingContext != nil);

	IRCChannelUser *cellItem = self.cellItem;

	IRCUserRank userRank = IRCUserRankNone;

	if ([TPCPreferences memberListSortFavorsServerStaff] && cellItem.user.isIRCop) {
		userRank = IRCUserRankIRCopByMode;
	}

	if (userRank == IRCUserRankNone) {
		userRank = cellItem.rank;
	}

	NSImageView *statusImageView = self.statusImageView;

	NSString *symbolName = TVCMemberListCellSymbolNameForRank(userRank);

	if (symbolName == nil) {
		statusImageView.image = nil;
		statusImageView.hidden = YES;

		return;
	}

	NSImage *symbol = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil];

	symbol = [symbol
		imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:11.0
																					 weight:NSFontWeightMedium]];

	statusImageView.image = symbol;
	statusImageView.hidden = NO;

	/* The accent fill is only drawn while the window is active; an
	 inactive selection is grey and keeps the rank colour legible. */
	if (drawingContext.isSelected && drawingContext.isWindowActive) {
		statusImageView.contentTintColor = [NSColor alternateSelectedControlTextColor];
	} else {
		NSColor *rankColor = TVCMemberListCellColorForRank(userRank);

		statusImageView.contentTintColor = (rankColor ?: [NSColor secondaryLabelColor]);
	}

	/* The rank is already part of the label's description. */
	statusImageView.cell.accessibilityElement = NO;
}

#pragma mark -
#pragma mark Expansion Frame

- (void)drawWithExpansionFrame
{
	TVCMemberList *memberList = self.memberList;

	TVCMemberListUserInfoPopover *userInfoPopover = memberList.memberListUserInfoPopover;

	IRCChannelUser *cellItem = self.cellItem;

	/* =============================================== */

	NSString *nickname = cellItem.user.nickname;

	userInfoPopover.nicknameField.stringValue = nickname;

	NSImageView *avatarImageView = userInfoPopover.avatarImageView;

	avatarImageView.image = [self.class avatarImageForNickname:nickname size:NSHeight(avatarImageView.bounds)];

	avatarImageView.cell.accessibilityElement = NO;

	/* =============================================== */

	NSString *hostmaskUsername = cellItem.user.username;

	if (hostmaskUsername.length == 0) {
		hostmaskUsername = TXTLS(@"TVCMainWindow[d85-9n]");
	}

	userInfoPopover.usernameField.stringValue = hostmaskUsername;

	/* =============================================== */

	BOOL stripIRCFormatting = [TPCPreferences removeAllFormatting];

	NSString *hostmaskAddress = cellItem.user.address;

	if (hostmaskAddress.length == 0) {
		hostmaskAddress = TXTLS(@"TVCMainWindow[d85-9n]");
	}

	if (stripIRCFormatting) {
		userInfoPopover.addressField.stringValue = hostmaskAddress;
	} else {
		NSAttributedString *hostmaskAddressFormatted =
			[hostmaskAddress attributedStringWithIRCFormatting:userInfoPopover.addressField.font
											preferredFontColor:nil
									 honorFormattingPreference:NO];

		userInfoPopover.addressField.attributedStringValue = hostmaskAddressFormatted;
	}

	/* =============================================== */

	NSString *realName = cellItem.user.realName;

	if (realName.length == 0) {
		realName = TXTLS(@"TVCMainWindow[d85-9n]");
	}

	if (stripIRCFormatting) {
		userInfoPopover.realNameField.stringValue = realName;
	} else {
		NSAttributedString *realNameFormatted =
			[realName attributedStringWithIRCFormatting:userInfoPopover.realNameField.font
									 preferredFontColor:nil
							  honorFormattingPreference:NO];

		userInfoPopover.realNameField.attributedStringValue = realNameFormatted;
	}

	/* =============================================== */

	NSString *account = cellItem.user.account;

	if (account.length == 0) {
		userInfoPopover.accountField.stringValue = TXTLS(@"TVCMainWindow[acc-nl]");
	} else {
		userInfoPopover.accountField.stringValue = account;
	}

	/* =============================================== */

	if (cellItem.user.isAway) {
		userInfoPopover.awayStatusField.stringValue = TXTLS(@"TVCMainWindow[jkr-ed]");
	} else {
		userInfoPopover.awayStatusField.stringValue = TXTLS(@"TVCMainWindow[gi6-wf]");
	}

	/* =============================================== */

	NSString *privileges = [self.class privilegesDescriptionForUser:cellItem];

	if (cellItem.user.isBot) {
		privileges = [NSString stringWithFormat:@"%@ (%@)", privileges, TXTLS(@"TVCMainWindow[b0t-lb]")];
	}

	userInfoPopover.privilegesField.stringValue = privileges;

	/* =============================================== */

	NSInteger rowIndex = [memberList rowForView:self];

	NSRect cellFrame = [memberList frameOfCellAtColumn:0 row:rowIndex];

	/* Presenting the popover will steal focus. To workaround this,
	 we record the active first responder then set it back. */
	NSWindow *window = self.window;

	NSResponder *activeFirstResponder = window.firstResponder;

	[userInfoPopover showRelativeToRect:cellFrame ofView:memberList preferredEdge:NSMaxXEdge];

	[window makeFirstResponder:activeFirstResponder];
}

- (TVCMemberListRowCell *)rowCell
{
	return (id)self.superview;
}

- (IRCChannelUser *)cellItem
{
	return self.objectValue;
}

- (TVCMemberList *)memberList
{
	return self.rowCell.memberList;
}

- (TVCMemberListCellDrawingContext *)drawingContext
{
	TVCMemberList *memberList = self.memberList;

	NSInteger rowIndex = [memberList rowForView:self];

	TVCMemberListCellDrawingContext *drawingContext = [TVCMemberListCellDrawingContext new];

	TVCMainWindow *mainWindow = self.mainWindow;

	drawingContext.isSelected = [memberList isRowSelected:rowIndex];
	drawingContext.isWindowActive = mainWindow.isActiveForDrawing;

	return drawingContext;
}

@end

@implementation TVCMemberListCellDrawingContext
@end

#pragma mark -
#pragma mark Header Cell

@implementation TVCMemberListHeaderCell

- (void)setObjectValue:(nullable id)objectValue
{
	super.objectValue = objectValue;

	TVCMemberListSection *section = objectValue;

	if ([section isKindOfClass:[TVCMemberListSection class]] == NO) {
		return;
	}

	NSTextField *textField = self.textField;

	NSString *title = section.title.localizedUppercaseString;

	textField.stringValue = title;

	/* Source list section headers are small, bold and secondary; the
	 system does not restyle a custom cell view so it is done here. */
	textField.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightBold];
	textField.textColor = [NSColor secondaryLabelColor];

	self.accessibilityLabel = section.title;
}

@end

#pragma mark -
#pragma mark Row View Cell

@implementation TVCMemberListRowCell

- (instancetype)initWithMemberList:(TVCMemberList *)memberList
{
	NSParameterAssert(memberList != nil);

	if ((self = [super initWithFrame:NSZeroRect])) {
		self.memberList = memberList;

		return self;
	}

	return nil;
}

- (void)setSelected:(BOOL)selected
{
	super.selected = selected;

	if (selected == NO && self.invalidatingBackgroundForSelection) {
		return;
	}

	[self setNeedsDisplayOnChild];
}

- (void)setNeedsDisplayOnChild
{
	self.childCell.needsDisplay = YES;
}

#pragma mark -
#pragma mark Emphasis

/* AppKit emphasizes a selection only while the window is key. Mail and
 Finder keep the accent fill while a sheet or panel is key, so emphasis
 follows main-window status instead. Both the getter and the background
 style are overridden so that drawing and text colours agree regardless
 of whether AppKit consults the accessor or the stored value. */
- (BOOL)isEmphasized
{
	NSWindow *window = self.window;

	if (window == nil) {
		return super.isEmphasized;
	}

	return window.isMainWindow;
}

- (void)setEmphasized:(BOOL)emphasized
{
	NSWindow *window = self.window;

	super.emphasized = ((window) ? window.isMainWindow : emphasized);

	[self setNeedsDisplayOnChild];
}

- (void)refreshEmphasis
{
	self.emphasized = self.isEmphasized;
}

- (NSBackgroundStyle)interiorBackgroundStyle
{
	if (self.isSelected && self.isEmphasized) {
		return NSBackgroundStyleEmphasized;
	}

	return super.interiorBackgroundStyle;
}

#pragma mark -
#pragma mark Cell Information

- (TVCMemberListCell *_Nullable)childCell
{
	if (self->_childCell == nil) {
		if (self.numberOfColumns == 0) {
			return nil;
		}

		self->_childCell = [self viewAtColumn:0];
	}

	return self->_childCell;
}

@end

NS_ASSUME_NONNULL_END
