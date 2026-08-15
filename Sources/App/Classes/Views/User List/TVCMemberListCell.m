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
#import "NSTableViewHelperPrivate.h"
#import "NSColorHelper.h"
#import "NSViewHelperPrivate.h"
#import "TPCPreferencesUserDefaults.h"
#import "TLOLocalization.h"
#import "TPCPreferencesLocal.h"
#import "IRCChannelUser.h"
#import "IRCUser.h"
#import "TVCMainWindow.h"
#import "TVCMemberListPrivate.h"
#import "TVCMemberListUserInfoPopoverPrivate.h"
#import "TVCMemberListCellPrivate.h"

NS_ASSUME_NONNULL_BEGIN

@class TVCMemberListCellDrawingContext;

@interface TVCMemberListRowCell ()
@property (nonatomic, weak) TVCMemberList *memberList;
@property (nonatomic, weak) TVCMemberListCell *childCell;
@end

@interface TVCMemberListCell ()
@property (nonatomic, weak) IBOutlet NSTextField *cellTextField;
@property (readonly, copy) TVCMemberListCellDrawingContext *drawingContext;
@property (readonly) TVCMemberList *memberList;
@property (readonly) TVCMemberListRowCell *rowCell;
@property (readonly) IRCChannelUser *cellItem;
@property (readonly) NSInteger rowIndex;
@end

@interface TVCMemberListCellDrawingContext : NSObject
@property (nonatomic, assign) BOOL isSelected;
@property (nonatomic, assign) BOOL isWindowActive;
@end

@implementation TVCMemberListCell

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

	[self updateDrawingInContext:drawingContext];

	[self updateMarkBadgeInContext:drawingContext];
}

- (void)updateTextFieldInContext:(TVCMemberListCellDrawingContext *)drawingContext
{
	NSParameterAssert(drawingContext != nil);

	/* Update string value */
	IRCChannelUser *cellItem = self.cellItem;

	NSString *stringValueNew = cellItem.user.nickname;

	NSTextField *textField = self.cellTextField;

	NSString *stringValueOld = textField.stringValue;

	if ([stringValueOld isEqualTo:stringValueNew]) {
		return;
	}

	textField.stringValue = stringValueNew;

	/* Update accessibility */
	NSTextFieldCell *textFieldCell = textField.cell;

	[textFieldCell setAccessibilityValueDescription:TXTLS(@"Accessibility[alq-6s]", stringValueNew)];
}

- (void)updateDrawingInContext:(TVCMemberListCellDrawingContext *)drawingContext
{
	NSParameterAssert(drawingContext != nil);

	self.cellTextField.attributedStringValue = [self attributedTextFieldValue];
}

- (NSAttributedString *)attributedTextFieldValue
{
	IRCChannelUser *cellItem = self.cellItem;

	NSTextField *textField = self.cellTextField;

	NSAttributedString *stringValue = textField.attributedStringValue;

	NSMutableAttributedString *mutableStringValue = [stringValue mutableCopy];

	[mutableStringValue beginEditing];

	NSFont *controlFont = [NSFont systemFontOfSize:NSFont.systemFontSize];

	NSColor *controlColor = (cellItem.user.isAway ? [NSColor secondaryLabelColor] : [NSColor labelColor]);

	NSRange stringValueRange = stringValue.range;

	[mutableStringValue addAttribute:NSFontAttributeName value:controlFont range:stringValueRange];
	[mutableStringValue addAttribute:NSForegroundColorAttributeName value:controlColor range:stringValueRange];

	[mutableStringValue endEditing];

	return mutableStringValue;
}

#pragma mark -
#pragma mark Badge Drawing

/* Mode badge colours are user configurable; everything that is not
 configurable comes from the system so the badge tracks the user's accent
 colour and appearance without a private colour table. */
static NSColor * _Nullable TVCMemberListCellUserModeColor(NSString *defaultsKey)
{
	NSColor *color = [RZUserDefaults() colorForKey:defaultsKey];

	if (color == nil || [color isEqual:[NSColor clearColor]]) {
		return nil;
	}

	return [color colorWithAlphaComponent:0.7];
}

static NSColor * _Nullable TVCMemberListCellColorForRank(IRCUserRank userRank)
{
	switch (userRank) {
		case IRCUserRankIRCopByMode:		return TVCMemberListCellUserModeColor(@"User List Mode Badge Colors -> +y");
		case IRCUserRankChannelOwner:		return TVCMemberListCellUserModeColor(@"User List Mode Badge Colors -> +q");
		case IRCUserRankSuperOperator:		return TVCMemberListCellUserModeColor(@"User List Mode Badge Colors -> +a");
		case IRCUserRankNormalOperator:		return TVCMemberListCellUserModeColor(@"User List Mode Badge Colors -> +o");
		case IRCUserRankHalfOperator:		return TVCMemberListCellUserModeColor(@"User List Mode Badge Colors -> +h");
		case IRCUserRankVoiced:				return TVCMemberListCellUserModeColor(@"User List Mode Badge Colors -> +v");
		default:							return TVCMemberListCellUserModeColor(@"User List Mode Badge Colors -> no mode");
	}
}

- (void)updateMarkBadgeInContext:(TVCMemberListCellDrawingContext *)drawingContext
{
	NSParameterAssert(drawingContext != nil);

	BOOL isSelected = drawingContext.isSelected;

	IRCChannelUser *cellItem = self.cellItem;

	NSString *modeSymbol = cellItem.mark;

	IRCUserRank userRankToDraw = IRCUserRankNone;

	if ([TPCPreferences memberListSortFavorsServerStaff]) {
		if (cellItem.user.isIRCop) {
			userRankToDraw = IRCUserRankIRCopByMode;
		}
	}

	if (userRankToDraw == IRCUserRankNone) {
		userRankToDraw = cellItem.rank;
	}

	self.imageView.image = [self markBadgeForRank:userRankToDraw symbol:modeSymbol isSelected:isSelected];
}

/* Returns nil when the image view has not been laid out yet. The caller assigns
 the result straight to -[NSImageView image], which takes nil, so the type is
 annotated rather than the nil replaced with an empty image. */
- (nullable NSImage *)markBadgeForRank:(IRCUserRank)userRank symbol:(NSString *)modeSymbol isSelected:(BOOL)isSelected
{
	NSRect badgeFrame = self.imageView.bounds;

	if (NSIsEmptyRect(badgeFrame)) {
		return nil;
	}

	NSString *stringToDraw = modeSymbol;

	if (stringToDraw.length == 0 && [TPCPreferences memberListDisplayNoModeSymbol]) {
		stringToDraw = @"\u00d7";
	}

	NSColor *backgroundColor = nil;
	NSColor *textColor = nil;

	if (isSelected) {
		/* Invert against the row's selection fill so the badge stays legible. */
		backgroundColor = [NSColor alternateSelectedControlTextColor];
		textColor = [NSColor selectedContentBackgroundColor];
	} else {
		backgroundColor = TVCMemberListCellColorForRank(userRank);

		if (backgroundColor == nil) {
			/* tertiaryLabelColor is already translucent; scaling it again left the
			 capsule at roughly 9% alpha. See the matching note in the server list. */
			backgroundColor = [NSColor secondarySystemFillColor];
		}

		textColor = [NSColor labelColor];
	}

	NSMutableParagraphStyle *paragraphStyle = [NSMutableParagraphStyle new];
	paragraphStyle.alignment = NSTextAlignmentCenter;

	NSFont *controlFont = [NSFont monospacedDigitSystemFontOfSize:11.0 weight:NSFontWeightMedium];

	NSAttributedString *badgeText =
	[NSAttributedString attributedStringWithString:stringToDraw
										attributes:@{
		NSForegroundColorAttributeName: textColor,
		NSFontAttributeName: controlFont,
		NSParagraphStyleAttributeName: paragraphStyle
	}];

	return [NSImage imageWithSize:badgeFrame.size flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
		[backgroundColor setFill];

		[[NSBezierPath bezierPathWithRoundedRect:dstRect
										 xRadius:(NSHeight(dstRect) / 2.0)
										 yRadius:(NSHeight(dstRect) / 2.0)] fill];

		if (stringToDraw.length == 0) {
			return YES;
		}

		/* Centre on the font's cap height rather than nudging per-glyph. */
		NSRect textRect = dstRect;
		textRect.origin.y = (NSMidY(dstRect) - (controlFont.capHeight / 2.0) + controlFont.descender);
		textRect.size.height = (NSHeight(dstRect) - NSMinY(textRect));

		[badgeText drawInRect:textRect];

		return YES;
	}];
}

#pragma mark -
#pragma mark Expansion Frame

- (void)drawWithExpansionFrame
{
	TVCMemberList *memberList = self.memberList;

	TVCMemberListUserInfoPopover *userInfoPopover = memberList.memberListUserInfoPopover;

	IRCChannelUser *cellItem = self.cellItem;

	/* =============================================== */

	userInfoPopover.nicknameField.stringValue = cellItem.user.nickname;

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
		[hostmaskAddress attributedStringWithIRCFormatting:[NSFont systemFontOfSize:12.0]
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
		[realName attributedStringWithIRCFormatting:[NSFont systemFontOfSize:12.0]
								 preferredFontColor:nil
						  honorFormattingPreference:NO];

		userInfoPopover.realNameField.attributedStringValue = realNameFormatted;
	}

	/* =============================================== */

	if (cellItem.user.isAway) {
		userInfoPopover.awayStatusField.stringValue = TXTLS(@"TVCMainWindow[jkr-ed]");
	} else {
		userInfoPopover.awayStatusField.stringValue = TXTLS(@"TVCMainWindow[gi6-wf]");
	}

	/* =============================================== */

	IRCUserRank userRank = cellItem.rank;

	if (cellItem.user.isIRCop) {
		userRank = IRCUserRankIRCopByMode;
	}

	NSString *userPrivileges = nil;

	if (userRank == IRCUserRankIRCopByMode) {
		userPrivileges = TXTLS(@"TVCMainWindow[i8t-vb]");
	} else if (userRank == IRCUserRankChannelOwner) {
		userPrivileges = TXTLS(@"TVCMainWindow[p1z-sc]");
	} else if (userRank == IRCUserRankSuperOperator) {
		userPrivileges = TXTLS(@"TVCMainWindow[som-zo]");
	} else if (userRank == IRCUserRankNormalOperator) {
		userPrivileges = TXTLS(@"TVCMainWindow[0kn-s5]");
	} else if (userRank == IRCUserRankHalfOperator) {
		userPrivileges = TXTLS(@"TVCMainWindow[0nn-te]");
	} else if (userRank == IRCUserRankVoiced) {
		userPrivileges = TXTLS(@"TVCMainWindow[ya1-sk]");
	} else {
		userPrivileges = TXTLS(@"TVCMainWindow[tjj-z2]");
	}

	userInfoPopover.privilegesField.stringValue = userPrivileges;

	/* =============================================== */

	NSInteger rowIndex = [memberList rowForView:self];

	NSRect cellFrame = [memberList frameOfCellAtColumn:0 row:rowIndex];

	/* Presenting the popover will steal focus. To workaround this,
	 we record the active first responder then set it back. */
	NSWindow *window = self.window;

	NSResponder *activeFirstResponder = window.firstResponder;

	[userInfoPopover showRelativeToRect:cellFrame
								 ofView:memberList
						  preferredEdge:NSMaxXEdge];

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

- (void)drawSelectionInRect:(NSRect)dirtyRect
{
	[super drawSelectionInRect:dirtyRect];
}

#pragma mark -
#pragma mark Cell Information

- (TVCMemberListCell * _Nullable)childCell
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
