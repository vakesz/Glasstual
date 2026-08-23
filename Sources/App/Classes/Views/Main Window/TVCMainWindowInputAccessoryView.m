/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
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

#import "TLOLocalization.h"
#import "TVCMainWindowInputAccessoryViewPrivate.h"

NS_ASSUME_NONNULL_BEGIN

#define _rowSpacing 4.0
#define _bottomGap 4.0
#define _typingRowHeight 18.0
#define _replyBannerHeight 30.0

@interface TVCMainWindowInputAccessoryView ()
@property(nonatomic, strong) NSStackView *stackView;

@property(nonatomic, strong) NSView *replyBanner;
@property(nonatomic, strong) NSTextField *replyLabel;
@property(nonatomic, strong) NSButton *replyCloseButton;
@property(nonatomic, copy, readwrite, nullable) NSString *replyMessageIdentifier;

@property(nonatomic, strong) NSView *typingRow;
@property(nonatomic, strong) NSImageView *typingSymbol;
@property(nonatomic, strong) NSTextField *typingLabel;
@end

@implementation TVCMainWindowInputAccessoryView

- (instancetype)initWithFrame:(NSRect)frameRect
{
	if ((self = [super initWithFrame:frameRect])) {
		[self buildSubviews];
	}

	return self;
}

- (BOOL)allowsVibrancy
{
	return NO;
}

- (void)buildSubviews
{
	self.translatesAutoresizingMaskIntoConstraints = NO;

	NSStackView *stackView = [NSStackView stackViewWithViews:@[]];

	stackView.orientation = NSUserInterfaceLayoutOrientationVertical;
	stackView.alignment = NSLayoutAttributeLeading;
	stackView.spacing = _rowSpacing;
	stackView.detachesHiddenViews = YES;
	stackView.translatesAutoresizingMaskIntoConstraints = NO;

	[self addSubview:stackView];

	[NSLayoutConstraint activateConstraints:@[
		[stackView.topAnchor constraintEqualToAnchor:self.topAnchor],
		[stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
		[stackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
		[stackView.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor],
	]];

	self.stackView = stackView;

	[self buildReplyBanner];
	[self buildTypingRow];

	[stackView addArrangedSubview:self.replyBanner];
	[stackView addArrangedSubview:self.typingRow];

	[stackView.widthAnchor constraintEqualToAnchor:self.widthAnchor].active = YES;

	self.replyBanner.hidden = YES;
	self.typingRow.hidden = YES;
}

#pragma mark -
#pragma mark Reply Banner

- (void)buildReplyBanner
{
	NSView *banner = [[NSView alloc] initWithFrame:NSZeroRect];

	banner.translatesAutoresizingMaskIntoConstraints = NO;
	banner.wantsLayer = YES;
	banner.layer.cornerRadius = 8.0;
	banner.layer.cornerCurve = kCACornerCurveContinuous;

	NSImageView *icon = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"arrowshape.turn.up.left"
																  accessibilityDescription:nil]];

	icon.translatesAutoresizingMaskIntoConstraints = NO;
	icon.contentTintColor = [NSColor secondaryLabelColor];
	icon.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:12.0 weight:NSFontWeightMedium];

	NSTextField *label = [NSTextField labelWithString:@""];

	label.translatesAutoresizingMaskIntoConstraints = NO;
	label.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
	label.textColor = [NSColor labelColor];
	label.lineBreakMode = NSLineBreakByTruncatingTail;
	label.maximumNumberOfLines = 1;
	label.allowsDefaultTighteningForTruncation = YES;

	[label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
									forOrientation:NSLayoutConstraintOrientationHorizontal];

	NSButton *close = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"xmark.circle.fill"
														  accessibilityDescription:TXTLS(@"TVCMainWindow[rpl-cl]")]
										 target:self
										 action:@selector(cancelReply:)];

	close.translatesAutoresizingMaskIntoConstraints = NO;
	close.bordered = NO;
	close.bezelStyle = NSBezelStyleAccessoryBarAction;
	close.contentTintColor = [NSColor secondaryLabelColor];
	close.toolTip = TXTLS(@"TVCMainWindow[rpl-cl]");
	close.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:13.0 weight:NSFontWeightRegular];

	[banner addSubview:icon];
	[banner addSubview:label];
	[banner addSubview:close];

	[NSLayoutConstraint activateConstraints:@[
		[banner.heightAnchor constraintEqualToConstant:_replyBannerHeight],

		[icon.leadingAnchor constraintEqualToAnchor:banner.leadingAnchor constant:10.0],
		[icon.centerYAnchor constraintEqualToAnchor:banner.centerYAnchor],

		[label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:6.0],
		[label.centerYAnchor constraintEqualToAnchor:banner.centerYAnchor],
		[label.trailingAnchor constraintLessThanOrEqualToAnchor:close.leadingAnchor constant:-6.0],

		[close.trailingAnchor constraintEqualToAnchor:banner.trailingAnchor constant:-6.0],
		[close.centerYAnchor constraintEqualToAnchor:banner.centerYAnchor],
	]];

	self.replyBanner = banner;
	self.replyLabel = label;
	self.replyCloseButton = close;

	[self updateReplyBannerColors];
}

- (void)viewDidChangeEffectiveAppearance
{
	[super viewDidChangeEffectiveAppearance];

	[self updateReplyBannerColors];
}

- (void)updateReplyBannerColors
{
	[self.effectiveAppearance performAsCurrentDrawingAppearance:^{
		self.replyBanner.layer.backgroundColor = [NSColor quaternarySystemFillColor].CGColor;
	}];
}

- (void)showReplyToMessageIdentifier:(NSString *)messageIdentifier
							nickname:(nullable NSString *)nickname
							 excerpt:(nullable NSString *)excerpt
{
	NSParameterAssert(messageIdentifier != nil);

	self.replyMessageIdentifier = messageIdentifier;

	NSString *who = ((nickname.length > 0) ? nickname : TXTLS(@"TVCMainWindow[rpl-an]"));

	NSString *prefix = TXTLS(@"TVCMainWindow[rpl-to]", who);

	NSMutableAttributedString *text = [[NSMutableAttributedString alloc]
		initWithString:prefix
			attributes:@{
				NSFontAttributeName : [NSFont systemFontOfSize:[NSFont smallSystemFontSize]
														weight:NSFontWeightSemibold],
				NSForegroundColorAttributeName : [NSColor labelColor]
			}];

	if (excerpt.length > 0) {
		NSString *trimmed = [excerpt stringByReplacingOccurrencesOfString:@"\n" withString:@" "];

		[text appendAttributedString:[[NSAttributedString alloc]
										 initWithString:[NSString stringWithFormat:@": %@", trimmed]
											 attributes:@{
												 NSFontAttributeName :
													 [NSFont systemFontOfSize:[NSFont smallSystemFontSize]],
												 NSForegroundColorAttributeName : [NSColor secondaryLabelColor]
											 }]];
	}

	self.replyLabel.attributedStringValue = text;

	self.replyLabel.toolTip = excerpt;

	[self setView:self.replyBanner visible:YES];
}

- (void)hideReply
{
	if (self.replyMessageIdentifier == nil) {
		return;
	}

	self.replyMessageIdentifier = nil;

	[self setView:self.replyBanner visible:NO];
}

- (void)cancelReply:(nullable id)sender
{
	[self hideReply];

	if (self.cancelReplyBlock) {
		self.cancelReplyBlock();
	}
}

#pragma mark -
#pragma mark Typing Row

- (void)buildTypingRow
{
	NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];

	row.translatesAutoresizingMaskIntoConstraints = NO;

	NSImageView *symbol = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"ellipsis"
																	accessibilityDescription:nil]];

	symbol.translatesAutoresizingMaskIntoConstraints = NO;
	symbol.contentTintColor = [NSColor secondaryLabelColor];
	symbol.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:13.0 weight:NSFontWeightBold];

	NSTextField *label = [NSTextField labelWithString:@""];

	label.translatesAutoresizingMaskIntoConstraints = NO;
	label.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
	label.textColor = [NSColor secondaryLabelColor];
	label.lineBreakMode = NSLineBreakByTruncatingTail;
	label.maximumNumberOfLines = 1;

	[label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
									forOrientation:NSLayoutConstraintOrientationHorizontal];

	[row addSubview:symbol];
	[row addSubview:label];

	[NSLayoutConstraint activateConstraints:@[
		[row.heightAnchor constraintEqualToConstant:_typingRowHeight],

		[symbol.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:10.0],
		[symbol.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],

		[label.leadingAnchor constraintEqualToAnchor:symbol.trailingAnchor constant:5.0],
		[label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
		[label.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor constant:-10.0],
	]];

	self.typingRow = row;
	self.typingSymbol = symbol;
	self.typingLabel = label;
}

- (void)setTypingNicknames:(NSArray<NSString *> *)nicknames
{
	NSParameterAssert(nicknames != nil);

	if (nicknames.count == 0) {
		if (self.typingRow.hidden == NO) {
			[self.typingSymbol removeAllSymbolEffects];

			[self setView:self.typingRow visible:NO];
		}

		return;
	}

	NSString *caption = nil;

	if (nicknames.count == 1) {
		caption = TXTLS(@"TVCMainWindow[typ-1]", nicknames[0]);
	} else if (nicknames.count == 2) {
		caption = TXTLS(@"TVCMainWindow[typ-2]", nicknames[0], nicknames[1]);
	} else {
		caption = TXTLS(@"TVCMainWindow[typ-n]", @(nicknames.count));
	}

	self.typingLabel.stringValue = caption;

	self.typingRow.toolTip = [nicknames componentsJoinedByString:@", "];

	if (self.typingRow.hidden) {
		if (NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion == NO) {
			[self.typingSymbol
				addSymbolEffect:[[NSSymbolVariableColorEffect effect] effectWithCumulative].effectWithReversing
						options:[NSSymbolEffectOptions optionsWithRepeating]];
		}

		[self setView:self.typingRow visible:YES];
	}
}

#pragma mark -
#pragma mark Layout

- (void)setView:(NSView *)view visible:(BOOL)visible
{
	if (view.hidden == (visible == NO)) {
		return;
	}

	view.hidden = (visible == NO);

	if (self.contentDidChangeBlock) {
		self.contentDidChangeBlock();
	}
}

- (BOOL)hasContent
{
	return (self.replyBanner.hidden == NO || self.typingRow.hidden == NO);
}

- (CGFloat)preferredHeight
{
	CGFloat height = 0.0;

	NSUInteger rows = 0;

	if (self.replyBanner.hidden == NO) {
		height += _replyBannerHeight;

		rows += 1;
	}

	if (self.typingRow.hidden == NO) {
		height += _typingRowHeight;

		rows += 1;
	}

	if (rows == 0) {
		return 0.0;
	}

	return (height + ((rows - 1) * _rowSpacing) + _bottomGap);
}

@end

NS_ASSUME_NONNULL_END
