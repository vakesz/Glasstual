/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
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

#import "NSColorHelper.h"
#import "NSViewHelperPrivate.h"
#import "TPCPreferencesUserDefaults.h"
#import "TXGlobalModels.h"
#import "TLOLocalization.h"
#import "TPCPreferencesLocal.h"
#import "IRCClient.h"
#import "IRCChannel.h"
#import "TVCMainWindow.h"
#import "TVCServerListPrivate.h"
#import "TVCServerListCellPrivate.h"

NS_ASSUME_NONNULL_BEGIN

@class TVCServerListCellDrawingContext;

@interface TVCServerListRowCell ()
@property(nonatomic, weak) TVCServerList *serverList;
@property(nonatomic, weak) __kindof TVCServerListCell *childCell;
@property(readonly) BOOL isGroupItem;
@end

@interface TVCServerListCell ()
@property(nonatomic, weak) IBOutlet NSTextField *cellTextField;
@property(nonatomic, weak) IBOutlet NSImageView *messageCountBadgeImageView;
// Deactivating the constraints will dereference them.
// We need to maintain a strong reference.
@property(nonatomic, strong) IBOutlet NSLayoutConstraint *messageCountBadgeLeadingConstraint;
@property(nonatomic, strong) IBOutlet NSLayoutConstraint *messageCountBadgeTrailingConstraint;
@property(readonly) BOOL isGroupItem;
@property(readonly) TVCServerList *serverList;
@property(readonly) __kindof TVCServerListRowCell *rowCell;
@property(readonly) TVCServerListCellDrawingContext *drawingContext;
@property(readonly) IRCTreeItem *cellItem;
@end

@interface TVCServerListCellDrawingContext : NSObject
@property(nonatomic, assign) BOOL isActive;
@property(nonatomic, assign) BOOL isGroupItem;
@property(nonatomic, assign) BOOL isSelected;
@property(nonatomic, assign) BOOL isSelectedFrontmost;
@property(nonatomic, assign) BOOL isWindowActive;
@end

@implementation TVCServerListCell

#pragma mark -
#pragma mark Cell Drawing

- (void)defineConstraints
{
}

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
	TVCServerListCellDrawingContext *drawingContext = self.drawingContext;

	[self updateTextFieldInContext:drawingContext];

	[self updateDrawingInContext:drawingContext];
}

- (void)updateTextFieldInContext:(TVCServerListCellDrawingContext *)drawingContext
{
	NSParameterAssert(drawingContext != nil);

	/* Update string value */
	IRCTreeItem *cellItem = self.cellItem;

	NSString *stringValueNew = cellItem.label;

	NSTextField *textField = self.cellTextField;

	NSString *stringValueOld = textField.stringValue;

	if ([stringValueOld isEqualToString:stringValueNew] == NO) {
		textField.stringValue = stringValueNew;
	}

	/* The accessibility description spells out the state as well as the name, so
	 it is rebuilt on every pass. Returning early when only the name is unchanged
	 left VoiceOver announcing a channel as joined after it had been parted. */
	BOOL isActive = drawingContext.isActive;
	BOOL isGroupItem = drawingContext.isGroupItem;

	NSTextFieldCell *textFieldCell = textField.cell;

	NSString *accessibilityDescription = nil;

	if (isGroupItem) {
		if (isActive) {
			accessibilityDescription = TXTLS(@"Accessibility[bmy-d2]", stringValueNew);
		} else {
			accessibilityDescription = TXTLS(@"Accessibility[tu4-8u]", stringValueNew);
		} // isActive
	} else {
		IRCChannel *channel = (IRCChannel *)cellItem;

		if (channel.isChannel == NO) {
			accessibilityDescription = TXTLS(@"Accessibility[9sn-xp]", stringValueNew);
		} else {
			if (isActive) {
				accessibilityDescription = TXTLS(@"Accessibility[75f-og]", stringValueNew);
			} else {
				accessibilityDescription = TXTLS(@"Accessibility[edc-7o]", stringValueNew);
			} // isActive
		} // isChannel

		/* Unread and highlight counts are part of what the row
		 communicates visually (the badge), so they are spoken too. */
		NSString *unreadDescription = [self accessibilityUnreadDescriptionForChannel:channel];

		if (unreadDescription) {
			accessibilityDescription =
				TXTLS(@"TDCChannelSpotlightController[et7-c5]", accessibilityDescription, unreadDescription);
		}

		/* The symbol in front of the name repeats what the text
		 already says. Hide it from VoiceOver instead of giving it
		 an empty label which is read as "image". */
		self.imageView.cell.accessibilityElement = NO;
	} // isGroupItem

	textFieldCell.accessibilityValueDescription = accessibilityDescription;

	self.accessibilityLabel = accessibilityDescription;
}

- (nullable NSString *)accessibilityUnreadDescriptionForChannel:(IRCChannel *)channel
{
	NSParameterAssert(channel != nil);

	NSUInteger unreadCount = channel.treeUnreadCount;

	if (unreadCount == 0) {
		return nil;
	}

	NSString *unreadCountDescription = nil;

	if (unreadCount == 1) {
		unreadCountDescription = TXTLS(@"TDCChannelSpotlightController[43s-x4]", TXFormattedNumber(unreadCount));
	} else {
		unreadCountDescription = TXTLS(@"TDCChannelSpotlightController[vzj-30]", TXFormattedNumber(unreadCount));
	}

	NSUInteger nicknameHighlightCount = channel.nicknameHighlightCount;

	if (nicknameHighlightCount == 0 || channel.config.ignoreHighlights) {
		return unreadCountDescription;
	}

	NSString *nicknameHighlightCountDescription = nil;

	if (nicknameHighlightCount == 1) {
		nicknameHighlightCountDescription =
			TXTLS(@"TDCChannelSpotlightController[0lz-oh]", TXFormattedNumber(nicknameHighlightCount));
	} else {
		nicknameHighlightCountDescription =
			TXTLS(@"TDCChannelSpotlightController[c4u-21]", TXFormattedNumber(nicknameHighlightCount));
	}

	return TXTLS(@"TDCChannelSpotlightController[et7-c5]", unreadCountDescription, nicknameHighlightCountDescription);
}

- (void)updateDrawingInContext:(TVCServerListCellDrawingContext *)drawingContext
{
	NSParameterAssert(drawingContext != nil);

	BOOL isGroupItem = drawingContext.isGroupItem;
	BOOL isActive = drawingContext.isActive;

	if (isGroupItem == NO) {
		IRCTreeItem *cellItem = self.cellItem;

		IRCChannel *channel = (IRCChannel *)cellItem;

		NSString *symbolName = channel.isChannel ? @"number" : @"person.fill";

		NSImage *icon = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:channel.name];
		icon.template = YES;

		self.imageView.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:12.0
																							 weight:NSFontWeightMedium];
		self.imageView.contentTintColor = isActive ? [NSColor secondaryLabelColor] : [NSColor tertiaryLabelColor];
		self.imageView.image = icon;
	}

	self.cellTextField.attributedStringValue = [self attributedTextFieldValueInContext:drawingContext];

	if (isGroupItem == NO) {
		[self populateMessageCountBadgeInContext:drawingContext];
	}
}

- (NSAttributedString *)attributedTextFieldValueInContext:(TVCServerListCellDrawingContext *)drawingContext
{
	NSParameterAssert(drawingContext != nil);

	BOOL isActive = drawingContext.isActive;
	BOOL isGroupItem = drawingContext.isGroupItem;
	BOOL isSelected = drawingContext.isSelected;
	BOOL isHighlight = NO;
	BOOL isErroneous = NO;

	IRCTreeItem *cellItem = self.cellItem;

	if (isGroupItem == NO) {
		IRCChannel *associatedChannel = (id)cellItem;

		isErroneous = associatedChannel.errorOnLastJoinAttempt;

		isHighlight = (associatedChannel.nicknameHighlightCount > 0);
	}

	NSTextField *textField = self.cellTextField;

	NSAttributedString *stringValue = textField.attributedStringValue;

	NSMutableAttributedString *mutableStringValue = [stringValue mutableCopy];

	[mutableStringValue beginEditing];

	NSFont *controlFont = nil;
	NSColor *controlColor = nil;

	if (isGroupItem) {
		controlFont = [NSFont systemFontOfSize:NSFont.systemFontSize weight:NSFontWeightSemibold];
		controlColor = [NSColor labelColor];
	} else {
		controlFont = [NSFont systemFontOfSize:NSFont.systemFontSize];

		/* On a selected row the label colours are swapped by AppKit to suit
		 the selection fill; a fixed red or blue would not be. */
		if (isErroneous && isSelected == NO) {
			controlColor = [NSColor systemRedColor];
		} else if (isActive && isHighlight && isSelected == NO) {
			controlColor = [NSColor systemBlueColor];
		} else if (isActive == NO) {
			controlColor = [NSColor tertiaryLabelColor];
		} else {
			controlColor = [NSColor labelColor];
		}
	}

	NSRange stringValueRange = stringValue.range;

	if (controlFont) {
		[mutableStringValue addAttribute:NSFontAttributeName value:controlFont range:stringValueRange];
	}

	if (controlColor) {
		[mutableStringValue addAttribute:NSForegroundColorAttributeName value:controlColor range:stringValueRange];
	}

	/* Mark connections secured by TLS alongside the name they belong to, which
	 keeps the indicator visible for every connection instead of only whichever
	 one happens to be frontmost. */
	if (isGroupItem) {
		NSAttributedString *securedBadge = [self attributedSecuredBadgeForClient:(id)cellItem];

		if (securedBadge) {
			[mutableStringValue appendAttributedString:securedBadge];
		}
	}

	[mutableStringValue endEditing];

	return mutableStringValue;
}

- (nullable NSAttributedString *)attributedSecuredBadgeForClient:(IRCClient *)client
{
	if ([client isKindOfClass:[IRCClient class]] == NO || client.isSecured == NO) {
		return nil;
	}

	NSImageSymbolConfiguration *symbolConfiguration =
		[NSImageSymbolConfiguration configurationWithPointSize:9.0
														weight:NSFontWeightSemibold
														 scale:NSImageSymbolScaleSmall];

	NSImage *lockImage = [[NSImage imageWithSystemSymbolName:@"lock.fill"
									accessibilityDescription:TXTLS(@"TVCMainWindow[tb-cs]")]
		imageWithSymbolConfiguration:symbolConfiguration];

	if (lockImage == nil) {
		return nil;
	}

	NSTextAttachment *attachment = [NSTextAttachment new];

	attachment.image = lockImage;

	NSMutableAttributedString *badge = [[NSMutableAttributedString alloc] initWithString:@" "];

	[badge appendAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];

	[badge addAttribute:NSForegroundColorAttributeName
				  value:[NSColor secondaryLabelColor]
				  range:NSMakeRange(0, badge.length)];

	return badge;
}

#pragma mark -
#pragma mark Badge Drawing

/* Badge metrics track the sidebar's text size rather than a fixed table. */
static const CGFloat _unreadBadgeMinimumWidth = 22.0;
static const CGFloat _unreadBadgeHeight = 16.0;
static const CGFloat _unreadBadgeTextPadding = 7.0;

- (void)populateMessageCountBadge
{
	[self populateMessageCountBadgeInContext:self.drawingContext];
}

- (void)populateMessageCountBadgeInContext:(TVCServerListCellDrawingContext *)drawingContext
{
	NSParameterAssert(drawingContext != nil);

	BOOL isSelected = drawingContext.isSelected;
	BOOL isSelectedFrontmost = drawingContext.isSelectedFrontmost;
	BOOL isWindowActive = drawingContext.isWindowActive;
	BOOL multipleRowsSelected = (self.serverList.numberOfSelectedRows > 1);

	IRCChannel *associatedChannel = (id)self.cellItem;

	BOOL drawMessageBadge = (isSelected == NO || (isSelectedFrontmost == NO && isSelected && multipleRowsSelected) ||
							 (isWindowActive == NO && isSelected));

	if (associatedChannel.config.showTreeBadgeCount == NO) {
		drawMessageBadge = NO;
	}

	NSUInteger treeUnreadCount = associatedChannel.treeUnreadCount;

	BOOL isHighlight = (associatedChannel.nicknameHighlightCount > 0);

	if (associatedChannel.config.ignoreHighlights) {
		isHighlight = NO;
	}

	if (treeUnreadCount == 0 || drawMessageBadge == NO) {
		self.messageCountBadgeImageView.image = nil;
		self.messageCountBadgeImageView.cell.accessibilityElement = NO;

		/* Disable constraints when badge is not visible to
		 allow text field to hug the right of the table view. */
		self.messageCountBadgeLeadingConstraint.active = NO;
		self.messageCountBadgeTrailingConstraint.active = NO;

		return;
	}

	/* The inverted palette only matches the accent fill that is drawn
	 while the window is active; an inactive selection is grey. */
	self.messageCountBadgeImageView.image = [self messageCountBadgeForCount:treeUnreadCount
																isHighlight:isHighlight
																 isSelected:(isSelected && isWindowActive)];

	/* The count is already spoken as part of the row label; the badge
	 itself is decorative for VoiceOver. */
	self.messageCountBadgeImageView.cell.accessibilityElement = NO;

	self.messageCountBadgeLeadingConstraint.active = YES;
	self.messageCountBadgeTrailingConstraint.active = YES;
}

- (nullable NSColor *)messageCountBadgeHighlightColorByUser
{
	NSColor *color = [RZUserDefaults() colorForKey:@"Server List Unread Message Count Badge Colors -> Highlight"];

	if (color == nil || [color isEqual:[NSColor clearColor]]) {
		return nil;
	}

	return color;
}

- (NSImage *)messageCountBadgeForCount:(NSUInteger)messageCount
						   isHighlight:(BOOL)isHighlight
							isSelected:(BOOL)isSelected
{
	NSColor *backgroundColor = nil;
	NSColor *textColor = nil;

	if (isSelected) {
		/* Invert against the row's selection fill so the badge stays legible. */
		backgroundColor = [NSColor alternateSelectedControlTextColor];
		textColor = [NSColor selectedContentBackgroundColor];
	} else if (isHighlight) {
		backgroundColor = ([self messageCountBadgeHighlightColorByUser] ?: [NSColor controlAccentColor]);
		textColor = [NSColor alternateSelectedControlTextColor];
	} else {
		/* tertiaryLabelColor is already translucent; scaling it again left the
		 capsule at roughly 9% alpha, which read as no capsule at all. The system
		 fill colors are the semantic answer for a shape behind small text. */
		backgroundColor = [NSColor secondarySystemFillColor];
		textColor = [NSColor secondaryLabelColor];
	}

	NSFont *controlFont = [NSFont monospacedDigitSystemFontOfSize:11.0 weight:NSFontWeightMedium];

	NSMutableParagraphStyle *paragraphStyle = [NSMutableParagraphStyle new];
	paragraphStyle.alignment = NSTextAlignmentCenter;

	NSAttributedString *stringToDraw =
		[NSAttributedString attributedStringWithString:TXFormattedNumber(messageCount)
											attributes:@{
												NSForegroundColorAttributeName : textColor,
												NSFontAttributeName : controlFont,
												NSParagraphStyleAttributeName : paragraphStyle
											}];

	CGFloat badgeWidth = MAX((stringToDraw.size.width + (_unreadBadgeTextPadding * 2.0)), _unreadBadgeMinimumWidth);

	return [NSImage imageWithSize:NSMakeSize(badgeWidth, _unreadBadgeHeight)
						  flipped:NO
				   drawingHandler:^BOOL(NSRect dstRect) {
					   [backgroundColor setFill];

					   [[NSBezierPath bezierPathWithRoundedRect:dstRect
														xRadius:(NSHeight(dstRect) / 2.0)
														yRadius:(NSHeight(dstRect) / 2.0)] fill];

					   /* Centre on the font's cap height so the digits sit optically level. */
					   NSRect textRect = dstRect;
					   textRect.origin.y = (NSMidY(dstRect) - (controlFont.capHeight / 2.0) + controlFont.descender);
					   textRect.size.height = (NSHeight(dstRect) - NSMinY(textRect));

					   [stringToDraw drawInRect:textRect];

					   return YES;
				   }];
}

#pragma mark -
#pragma mark Cell Information

- (BOOL)isGroupItem
{
	return [self isKindOfClass:[TVCServerListCellGroupItem class]];
}

- (__kindof TVCServerListRowCell *)rowCell
{
	return (id)self.superview;
}

- (IRCTreeItem *)cellItem
{
	return self.objectValue;
}

- (TVCServerList *)serverList
{
	return self.rowCell.serverList;
}

- (TVCServerListCellDrawingContext *)drawingContext
{
	TVCServerList *serverList = self.serverList;

	IRCTreeItem *cellItem = self.cellItem;

	NSInteger rowIndex = [serverList rowForItem:cellItem];

	TVCMainWindow *mainWindow = self.mainWindow;

	TVCServerListCellDrawingContext *drawingContext = [TVCServerListCellDrawingContext new];

	drawingContext.isActive = cellItem.isActive;
	drawingContext.isGroupItem = self.isGroupItem;
	drawingContext.isSelected = [serverList isRowSelected:rowIndex];
	drawingContext.isSelectedFrontmost = [mainWindow isItemSelected:cellItem];
	drawingContext.isWindowActive = mainWindow.isActiveForDrawing;

	return drawingContext;
}

- (BOOL)needsDisplayWhenApplicationAppearanceChanges
{
	return NO;
}

- (BOOL)needsDisplayWhenSystemAppearanceChanges
{
	return NO;
}

@end

@implementation TVCServerListCellGroupItem
@end

@implementation TVCServerListCellChildItem

- (void)defineConstraints
{
	NSImageView *imageView = self.imageView;

	if (imageView == nil) {
		return;
	}

	imageView.imageScaling = NSImageScaleProportionallyUpOrDown;

	/* Only the width is pinned. Symbols differ in width, and the label is laid
	 out against the trailing edge of this view, so without a fixed width the
	 names in the list do not line up with one another. The height is left
	 alone: the nib already fixes it by insetting the image view from the top
	 and the bottom of the row, and adding a height here conflicts with that. */
	for (NSLayoutConstraint *constraint in imageView.constraints) {
		if (constraint.firstAttribute == NSLayoutAttributeWidth) {
			return;
		}
	}

	[imageView.widthAnchor constraintEqualToConstant:16.0].active = YES;
}

@end

@implementation TVCServerListCellDrawingContext
@end

#pragma mark -
#pragma mark Row Cell

@implementation TVCServerListRowCell

- (instancetype)initWithServerList:(TVCServerList *)serverList
{
	if ((self = [super initWithFrame:NSZeroRect])) {
		self.serverList = serverList;

		return self;
	}

	return nil;
}

- (void)drawDraggingDestinationFeedbackInRect:(NSRect)dirtyRect
{
	; // Do nothing for this...
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

- (void)didAddSubview:(NSView *)subview
{
	TVCServerListCellGroupItem *childCell = self.childCell;

	[childCell defineConstraints];

	[super didAddSubview:subview];
}

#pragma mark -
#pragma mark Cell Information

- (__kindof TVCServerListCell *_Nullable)childCell
{
	if (self->_childCell == nil) {
		if (self.numberOfColumns == 0) {
			return nil;
		}

		self->_childCell = [self viewAtColumn:0];
	}

	return self->_childCell;
}

- (BOOL)isGroupItem
{
	return [self isKindOfClass:[TVCServerListGroupRowCell class]];
}

#pragma mark -
#pragma mark Accessibility

- (nullable NSString *)accessibilityLabel
{
	NSString *label = self.childCell.accessibilityLabel;

	if (label.length > 0) {
		return label;
	}

	return [super accessibilityLabel];
}

@end

@implementation TVCServerListGroupRowCell
@end

@implementation TVCServerListChildRowCell
@end

NS_ASSUME_NONNULL_END
