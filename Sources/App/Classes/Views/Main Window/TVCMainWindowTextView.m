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

#import <QuartzCore/QuartzCore.h>

#import "NSViewHelperPrivate.h"
#import "IRCColorFormat.h"
#import "TLOLocalization.h"
#import "TPCResourceManagerPrivate.h"
#import "TPCPreferencesLocalPrivate.h"
#import "TPCPreferencesUserDefaults.h"
#import "TVCMainWindow.h"
#import "TXMasterController.h"
#import "TXSharedApplication.h"
#import "TVCTextViewWithIRCFormatterPrivate.h"
#import "TVCMainWindowTextViewAppearancePrivate.h"
#import "TVCMainWindowTextViewPrivate.h"
#import "TVCMainWindowInputAccessoryViewPrivate.h"
#import "IRCClientPrivate.h"
#import "IRCChannel.h"
#import "IRCTypingTrackerPrivate.h"

NS_ASSUME_NONNULL_BEGIN

#define _KeyObservingArray                                                                                             \
	@[                                                                                                                 \
		@"TextFieldAutomaticSpellCheck",                                                                               \
		@"TextFieldAutomaticGrammarCheck",                                                                             \
		@"TextFieldAutomaticSpellCorrection",                                                                          \
		@"TextFieldSmartCopyPaste",                                                                                    \
		@"TextFieldSmartQuotes",                                                                                       \
		@"TextFieldSmartDashes",                                                                                       \
		@"TextFieldSmartLinks",                                                                                        \
		@"TextFieldDataDetectors",                                                                                     \
		@"TextFieldTextReplacement"                                                                                    \
	]

@interface TVCMainWindowTextView ()
/* Not named placeholderAttributedString: NSTextView has a private
 accessor by that name which AppKit would start calling. */
@property(nonatomic, copy, nullable) NSAttributedString *inputPlaceholderAttributedString;
@property(nonatomic, weak) IBOutlet NSLayoutConstraint *textViewHeightConstraint;
@property(nonatomic, weak) IBOutlet NSLayoutConstraint *windowContentViewMinimumHeight;
@property(nonatomic, weak) IBOutlet TVCMainWindowTextViewContentView *contentView;
@property(nonatomic, weak) IBOutlet NSView *inputBarContainerView;
@property(nonatomic, weak) IBOutlet NSLayoutConstraint *inputBarTopConstraint;
@property(nonatomic, strong) TVCMainWindowInputAccessoryView *accessoryView;
@property(nonatomic, strong) NSLayoutConstraint *accessoryHeightConstraint;
@property(nonatomic, strong) NSLayoutConstraint *accessoryTopConstraint;
@property(nonatomic, assign) CGFloat accessoryHeight;
@property(nonatomic, assign) BOOL observingTyping;
/* The channel the last typing notification went to, so that it can be
 told "done" when the selection moves elsewhere. */
@property(nonatomic, weak, nullable) IRCChannel *typingChannel;
@property(nonatomic, strong) TVCMainWindowTextViewAppearance *userInterfaceObjects;
@property(nonatomic, assign) BOOL observingUserDefaults;
@property(readonly) NSArray<NSString *> *defaultSpellingIgnores;
@end

@interface TVCMainWindowTextViewContentView ()
@property(nonatomic, weak) IBOutlet TVCMainWindowTextView *textView;
@end

@implementation TVCMainWindowTextView

#pragma mark -
#pragma mark Drawing

- (void)awakeFromNib
{
	[super awakeFromNib];

	/* The height and caret logic is written against TextKit 2. AppKit
	 silently falls back to TextKit 1 when anything reads -layoutManager,
	 after which -textLayoutManager returns nil and the input field would
	 stop growing. Surface that instead of sizing by guesswork. */
	if (self.textLayoutManager == nil) {
		LogToConsoleError("Input text view is not using TextKit 2");
	}

	self.backgroundColor = [NSColor clearColor];

	/* The nib leaves the scroll view drawing its background, which paints
	 controlBackgroundColor (white in a light appearance) inside the glass the
	 input bar is hosted in. */
	self.enclosingScrollView.drawsBackground = NO;

	[self updateTextDirection];

	[self installAccessoryView];
}

#pragma mark -
#pragma mark Accessory Strip

/* The strip sits above the input bar container inside the content
 view. The nib pins the container to the top of the content view; that
 constraint is swapped for one that hangs the container off the strip.
 The strip's height is animated so the field slides rather than jumps. */
- (void)installAccessoryView
{
	TVCMainWindowTextViewContentView *contentView = self.contentView;

	NSView *container = self.inputBarContainerView;

	if (contentView == nil || container == nil || self.accessoryView != nil) {
		return;
	}

	TVCMainWindowInputAccessoryView *accessoryView = [[TVCMainWindowInputAccessoryView alloc] initWithFrame:NSZeroRect];

	[contentView addSubview:accessoryView];

	CGFloat topInset = self.inputBarTopConstraint.constant;

	self.inputBarTopConstraint.active = NO;

	NSLayoutConstraint *heightConstraint = [accessoryView.heightAnchor constraintEqualToConstant:0.0];

	NSLayoutConstraint *topConstraint = [container.topAnchor constraintEqualToAnchor:accessoryView.bottomAnchor];

	[NSLayoutConstraint activateConstraints:@[
		[accessoryView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:topInset],
		[accessoryView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
		[accessoryView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
		heightConstraint,
		topConstraint,
	]];

	accessoryView.clipsToBounds = YES;

	self.accessoryView = accessoryView;
	self.accessoryHeightConstraint = heightConstraint;
	self.accessoryTopConstraint = topConstraint;

	__weak TVCMainWindowTextView *weakSelf = self;

	accessoryView.contentDidChangeBlock = ^{
		[weakSelf accessoryContentDidChange];
	};

	accessoryView.cancelReplyBlock = ^{
		[weakSelf focus];
	};
}

- (void)accessoryContentDidChange
{
	CGFloat height = self.accessoryView.preferredHeight;

	if (height == self.accessoryHeight) {
		return;
	}

	self.accessoryHeight = height;

	BOOL reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;

	if (reduceMotion || self.window == nil) {
		self.accessoryHeightConstraint.constant = height;

		[self recalculateTextViewSizeForced:YES];

		return;
	}

	[NSAnimationContext
		runAnimationGroup:^(NSAnimationContext *context) {
			context.duration = 0.18;
			context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
			context.allowsImplicitAnimation = YES;

			self.accessoryHeightConstraint.animator.constant = height;

			[self recalculateTextViewSizeForced:YES animated:YES];
		}
		completionHandler:nil];
}

#pragma mark -
#pragma mark Replies

- (nullable NSString *)replyMessageIdentifier
{
	return self.accessoryView.replyMessageIdentifier;
}

- (void)beginReplyToMessageIdentifier:(NSString *)messageIdentifier
							 nickname:(nullable NSString *)nickname
							  excerpt:(nullable NSString *)excerpt
{
	NSParameterAssert(messageIdentifier != nil);

	[self.accessoryView showReplyToMessageIdentifier:messageIdentifier nickname:nickname excerpt:excerpt];

	[self focus];
}

- (void)cancelReply
{
	[self.accessoryView hideReply];
}

- (void)consumeReplyIntoClient:(nullable IRCClient *)client
{
	NSString *messageIdentifier = self.replyMessageIdentifier;

	if (messageIdentifier == nil) {
		return;
	}

	client.nextMessageReplyIdentifier = messageIdentifier;

	[self cancelReply];
}

#pragma mark -
#pragma mark Typing

- (void)setTypingObserved:(BOOL)observed
{
	if (self->_observingTyping == observed) {
		return;
	}

	self->_observingTyping = observed;

	if (observed) {
		[RZNotificationCenter() addObserver:self
								   selector:@selector(typingStateDidChange:)
									   name:IRCTypingTrackerDidChangeNotification
									 object:nil];

		[RZNotificationCenter() addObserver:self
								   selector:@selector(selectionDidChange:)
									   name:TVCMainWindowSelectionChangedNotification
									 object:nil];
	} else {
		[RZNotificationCenter() removeObserver:self name:IRCTypingTrackerDidChangeNotification object:nil];
		[RZNotificationCenter() removeObserver:self name:TVCMainWindowSelectionChangedNotification object:nil];
	}
}

- (void)typingStateDidChange:(NSNotification *)notification
{
	IRCChannel *channel = notification.userInfo[IRCTypingTrackerChannelKey];

	if (channel == nil || channel != mainWindow().selectedChannel) {
		return;
	}

	[self updateTypingRow];
}

- (void)selectionDidChange:(NSNotification *)notification
{
	IRCChannel *selectedChannel = mainWindow().selectedChannel;

	IRCChannel *previousChannel = self.typingChannel;

	if (previousChannel && previousChannel != selectedChannel) {
		[previousChannel.associatedClient localUserClearedTextInChannel:previousChannel];

		self.typingChannel = nil;
	}

	/* A reply belongs to the view it was started in. */
	[self cancelReply];

	[self updateTypingRow];
}

- (void)updateTypingRow
{
	IRCChannel *channel = mainWindow().selectedChannel;

	NSArray<NSString *> *nicknames = @[];

	if (channel && channel.isUtility == NO) {
		nicknames = [channel.associatedClient.typingTracker typingNicknamesInChannel:channel];
	}

	[self.accessoryView setTypingNicknames:nicknames];
}

- (void)noteTextChangedForTyping
{
	IRCChannel *channel = mainWindow().selectedChannel;

	IRCClient *client = channel.associatedClient;

	if (channel == nil || client == nil) {
		return;
	}

	NSString *text = self.stringValue;

	[client noteLocalUserTyping:text inChannel:channel];

	if (text.length == 0 || [text hasPrefix:@"/"]) {
		self.typingChannel = nil;
	} else {
		self.typingChannel = channel;
	}
}

/* -viewDidMoveToWindow is not guaranteed to alternate between a window and nil.
 It also fires when the view is reparented inside the window it is already in,
 which is exactly what the main window does when it moves the input bar into the
 glass that hosts it. Registering on every call left a second set of observers
 behind each time, and the matching -removeObserver: for a registration that was
 never made raises. The flag makes both directions idempotent. */
- (void)viewDidMoveToWindow
{
	[super viewDidMoveToWindow];

	[self setUserDefaultsObserved:(self.window != nil)];

	[self setTypingObserved:(self.window != nil)];
}

- (void)setUserDefaultsObserved:(BOOL)observed
{
	if (self->_observingUserDefaults == observed) {
		return;
	}

	self->_observingUserDefaults = observed;

	for (NSString *key in _KeyObservingArray) {
		if (observed) {
			[RZUserDefaults() addObserver:self
							   forKeyPath:key
								  options:(NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew)
								  context:NULL];
		} else {
			[RZUserDefaults() removeObserver:self forKeyPath:key];
		}
	}
}

- (void)dealloc
{
	[self setUserDefaultsObserved:NO];
}

- (void)updateVibrancyWithAppearance:(TVCMainWindowTextViewAppearance *)appearance
{
	NSParameterAssert(appearance != nil);

	self.contentView.needsDisplay = YES;
}

- (void)applicationAppearanceChanged
{
	TVCMainWindowTextViewAppearance *appearance = self.mainWindow.userInterfaceObjects.textView;

	[self _updateAppearance:appearance];
}

/*
- (void)systemAppearanceChanged
{

}
*/

- (void)_updateAppearance:(TVCMainWindowTextViewAppearance *)appearance
{
	NSParameterAssert(appearance != nil);

	self.userInterfaceObjects = appearance;

	[self updateVibrancyWithAppearance:appearance];

	self.textContainerInset = appearance.textViewInset;

	self.preferredFontColor = appearance.textViewTextColor;

	[self updateTextBoxCachedPreferredFontSize];

	[self resetTypeSetterAttributes];

	[self updateAllFontColorsToMatchTheDefaultFont];
}

#pragma mark -
#pragma mark Spelling

- (void)resetSpellingIgnores
{
	/* When performing nickname completion, completions are
	 added to the ignore list. The main window then resets
	 the entire spelling ignore list, by calling this method
	 when the selection changes. */
	/* Because the main window will eventually call this for us,
	 we allow it to happen lazily, instead of in awake from nib. */
	[RZSpellChecker() setIgnoredWords:self.defaultSpellingIgnores inSpellDocumentWithTag:self.spellCheckerDocumentTag];
}

- (NSArray<NSString *> *)defaultSpellingIgnores
{
	return [TPCResourceManager arrayFromResources:@"StaticStore" key:@"Spelling Ignores"];
}

#pragma mark -
#pragma mark Utilities

- (void)updateAllFontColorsToMatchTheDefaultFont
{
	[self.textStorage beginEditing];

	[self.textStorage enumerateAttributesInRange:self.range
										 options:0
									  usingBlock:^(NSDictionary *attributes, NSRange effectiveRange, BOOL *stop) {
										  if ([attributes containsKey:IRCTextFormatterForegroundColorAttributeName]) {
											  return;
										  }

										  [self resetFontColorInRange:effectiveRange];
									  }];

	[self.textStorage endEditing];
}

- (void)setAttributedStringValue:(NSAttributedString *)attributedStringValue
{
	super.attributedStringValue = attributedStringValue;

	[self updateAllFontColorsToMatchTheDefaultFont];
}

- (void)updateTextDirection
{
	if ([TPCPreferences rightToLeftFormatting]) {
		self.baseWritingDirection = NSWritingDirectionRightToLeft;
	} else {
		self.baseWritingDirection = NSWritingDirectionLeftToRight;
	}
}

- (void)textDidChange:(NSNotification *)aNotification
{
	[super textDidChange:aNotification];

	[self recalculateTextViewSize];

	[self noteTextChangedForTyping];
}

- (void)paste:(nullable id)sender
{
	[super paste:self];

	[self recalculateTextViewSize];
}

- (BOOL)textView:(NSTextView *)aTextView doCommandBySelector:(SEL)aSelector
{
	if (aSelector == @selector(insertNewline:)) {
		[self.mainWindow textEntered];

		return YES;
	}

	/* Escape leaves a reply. */
	if (aSelector == @selector(cancelOperation:) && self.replyMessageIdentifier != nil) {
		[self cancelReply];

		return YES;
	}

	return NO;
}

#pragma mark -
#pragma mark Multi-line Text Box Drawing

- (void)drawRect:(NSRect)dirtyRect
{
	if ([self needsToDrawRect:dirtyRect] == NO) {
		return;
	}

	[super drawRect:dirtyRect];

	if (self.stringLength > 0) {
		return;
	}

	NSAttributedString *placeholder = self.inputPlaceholderAttributedString;

	if (placeholder == nil) {
		return;
	}

	/* The placeholder sits where the first line of text would: inside the
	 container inset and the line fragment padding, as tall as one line
	 of the preferred font. */
	NSTextContainer *textContainer = self.textContainer;

	CGFloat padding = textContainer.lineFragmentPadding;

	NSPoint origin = self.textContainerOrigin;

	NSRect placeholderRect = NSMakeRect(
		(origin.x + padding), origin.y, (textContainer.size.width - (padding * 2.0)), self.defaultLineHeight);

	[placeholder drawInRect:placeholderRect];
}

- (void)updateTextBoxCachedPreferredFontSize
{
	/* Update font */
	TVCMainWindowTextViewAppearance *appearance = self.userInterfaceObjects;

	if ([appearance preferredTextViewFontChanged] == NO) {
		return;
	}

	NSFont *preferredFont = appearance.textViewPreferredFont;

	self.preferredFont = preferredFont;

	/* Update the placeholder string */
	NSColor *placeholderTextColor = appearance.textViewPlaceholderTextColor;

	/* The paragraph style follows the view's writing direction so
	 the placeholder sits on the correct side for right to left users. */
	NSMutableParagraphStyle *paragraphStyle = [NSMutableParagraphStyle new];

	paragraphStyle.baseWritingDirection = self.baseWritingDirection;
	paragraphStyle.alignment = NSTextAlignmentNatural;
	paragraphStyle.lineBreakMode = NSLineBreakByTruncatingTail;

	NSDictionary *placeholderStringAttributes = @{
		NSFontAttributeName : preferredFont,
		NSForegroundColorAttributeName : placeholderTextColor,
		NSParagraphStyleAttributeName : paragraphStyle
	};

	self.inputPlaceholderAttributedString =
		[NSAttributedString attributedStringWithString:TXTLS(@"TVCMainWindow[8r3-ih]")
											attributes:placeholderStringAttributes];

	self.needsDisplay = YES;
}

- (void)updateTextBasedOnPreferredFontSize
{
	TVCMainWindowTextViewAppearance *appearance = self.userInterfaceObjects;

	TVCMainWindowTextViewFontSize preferredFontSize = appearance.textViewPreferredFontSize;

	[self updateTextBoxCachedPreferredFontSize];

	if (appearance.textViewPreferredFontSize != preferredFontSize) {
		[self updateAllFontSizesToMatchTheDefaultFont];
	}

	[self recalculateTextViewSizeForced];
}

- (CGFloat)defaultLineHeight
{
	/* The height TextKit 2 gives one line of the preferred font. An empty
	 document has no line fragments to measure and its usage bounds do
	 not follow the typing attributes, so a sample is laid out with a
	 scratch layout manager. Measuring with TextKit 2 itself keeps the
	 empty and the one line states the same height. */
	NSTextContentStorage *contentStorage = [NSTextContentStorage new];
	NSTextLayoutManager *layoutManager = [NSTextLayoutManager new];

	[contentStorage addTextLayoutManager:layoutManager];

	layoutManager.textContainer = [[NSTextContainer alloc] initWithSize:NSMakeSize(10000.0, 10000.0)];

	contentStorage.attributedString =
		[[NSAttributedString alloc] initWithString:@"X" attributes:@{NSFontAttributeName : self.preferredFont}];

	[layoutManager ensureLayoutForRange:layoutManager.documentRange];

	return NSHeight([layoutManager usageBoundsForTextContainer]);
}

- (void)recalculateTextViewSize
{
	[self recalculateTextViewSizeForced:NO];
}

- (void)recalculateTextViewSizeForced
{
	[self recalculateTextViewSizeForced:YES];
}

- (void)recalculateTextViewSizeForced:(BOOL)forceRecalculate
{
	[self recalculateTextViewSizeForced:forceRecalculate animated:NO];
}

- (void)recalculateTextViewSizeForced:(BOOL)forceRecalculate animated:(BOOL)animated
{
	TVCMainWindowTextViewAppearance *appearance = self.userInterfaceObjects;

	/* Without an appearance the border padding reads as zero, which sizes the
	 content view to the bare line height. That is smaller than the insets the
	 nib places inside it, so the resulting layout is unsatisfiable and AppKit
	 spends startup breaking constraints. The nib's own height is correct until
	 the appearance arrives, and -updateTextBoxCachedPreferredFontSize
	 recalculates the size once it does. */
	if (appearance == nil) {
		return;
	}

	NSWindow *window = self.window;

	NSRect windowFrame = window.frame;

	CGFloat contentBorderPadding = appearance.backgroundViewContentBorderPadding;

	CGFloat backgroundHeight = 0;

	CGFloat backgroundHeightDefault = [self defaultLineHeight];

	if (self.stringLength < 1) {
		backgroundHeight = (backgroundHeightDefault + contentBorderPadding);
	} else {
		CGFloat backgroundHeightMaximum =
			(NSHeight(windowFrame) - (self.windowContentViewMinimumHeight.constant + contentBorderPadding));

		backgroundHeight = [self highestHeightBelowHeight:backgroundHeightMaximum withPadding:contentBorderPadding];

		if ((backgroundHeight - contentBorderPadding) < backgroundHeightDefault) {
			backgroundHeight = (backgroundHeightDefault + contentBorderPadding);
		}
	}

	/* The strip above the field adds its own height. */
	backgroundHeight += self.accessoryHeight;

	if (animated) {
		self.textViewHeightConstraint.animator.constant = backgroundHeight;
	} else {
		self.textViewHeightConstraint.constant = backgroundHeight;
	}

	id scrollViewContentView = self.enclosingScrollView.contentView;

	NSRect contentViewBounds = [scrollViewContentView bounds];

	if (contentViewBounds.origin.x > 0) {
		contentViewBounds.origin.x = 0;

		[scrollViewContentView scrollToPoint:contentViewBounds.origin];
	}
}

#pragma mark -
#pragma mark NSTextView Context Menu Preferences

- (void)observeValueForKeyPath:(nullable NSString *)keyPath
					  ofObject:(nullable id)object
						change:(nullable NSDictionary *)change
					   context:(nullable void *)context
{
	if ([keyPath isEqualToString:@"TextFieldAutomaticSpellCheck"]) {
		self.continuousSpellCheckingEnabled = [TPCPreferences textFieldAutomaticSpellCheck];
	} else if ([keyPath isEqualToString:@"TextFieldAutomaticGrammarCheck"]) {
		self.grammarCheckingEnabled = [TPCPreferences textFieldAutomaticGrammarCheck];
	} else if ([keyPath isEqualToString:@"TextFieldAutomaticSpellCorrection"]) {
		self.automaticSpellingCorrectionEnabled = [TPCPreferences textFieldAutomaticSpellCorrection];
	} else if ([keyPath isEqualToString:@"TextFieldSmartCopyPaste"]) {
		self.smartInsertDeleteEnabled = [TPCPreferences textFieldSmartCopyPaste];
	} else if ([keyPath isEqualToString:@"TextFieldSmartQuotes"]) {
		self.automaticQuoteSubstitutionEnabled = [TPCPreferences textFieldSmartQuotes];
	} else if ([keyPath isEqualToString:@"TextFieldSmartDashes"]) {
		self.automaticDashSubstitutionEnabled = [TPCPreferences textFieldSmartDashes];
	} else if ([keyPath isEqualToString:@"TextFieldSmartLinks"]) {
		self.automaticLinkDetectionEnabled = [TPCPreferences textFieldSmartLinks];
	} else if ([keyPath isEqualToString:@"TextFieldDataDetectors"]) {
		self.automaticDataDetectionEnabled = [TPCPreferences textFieldDataDetectors];
	} else if ([keyPath isEqualToString:@"TextFieldTextReplacement"]) {
		self.automaticTextReplacementEnabled = [TPCPreferences textFieldTextReplacement];
	} else if ([super respondsToSelector:@selector(observeValueForKeyPath:ofObject:change:context:)]) {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

- (void)setContinuousSpellCheckingEnabled:(BOOL)continuousSpellCheckingEnabled
{
	[TPCPreferences setTextFieldAutomaticSpellCheck:continuousSpellCheckingEnabled];

	super.continuousSpellCheckingEnabled = continuousSpellCheckingEnabled;
}

- (void)setGrammarCheckingEnabled:(BOOL)grammarCheckingEnabled
{
	[TPCPreferences setTextFieldAutomaticGrammarCheck:grammarCheckingEnabled];

	super.grammarCheckingEnabled = grammarCheckingEnabled;
}

- (void)setAutomaticSpellingCorrectionEnabled:(BOOL)automaticSpellingCorrectionEnabled
{
	[TPCPreferences setTextFieldAutomaticSpellCorrection:automaticSpellingCorrectionEnabled];

	super.automaticSpellingCorrectionEnabled = automaticSpellingCorrectionEnabled;
}

- (void)setSmartInsertDeleteEnabled:(BOOL)smartInsertDeleteEnabled
{
	[TPCPreferences setTextFieldSmartCopyPaste:smartInsertDeleteEnabled];

	super.smartInsertDeleteEnabled = smartInsertDeleteEnabled;
}

- (void)setAutomaticQuoteSubstitutionEnabled:(BOOL)automaticQuoteSubstitutionEnabled
{
	[TPCPreferences setTextFieldSmartQuotes:automaticQuoteSubstitutionEnabled];

	super.automaticQuoteSubstitutionEnabled = automaticQuoteSubstitutionEnabled;
}

- (void)setAutomaticDashSubstitutionEnabled:(BOOL)automaticDashSubstitutionEnabled
{
	[TPCPreferences setTextFieldSmartDashes:automaticDashSubstitutionEnabled];

	super.automaticDashSubstitutionEnabled = automaticDashSubstitutionEnabled;
}

- (void)setAutomaticLinkDetectionEnabled:(BOOL)automaticLinkDetectionEnabled
{
	[TPCPreferences setTextFieldSmartLinks:automaticLinkDetectionEnabled];

	super.automaticLinkDetectionEnabled = automaticLinkDetectionEnabled;
}

- (void)setAutomaticDataDetectionEnabled:(BOOL)automaticDataDetectionEnabled
{
	[TPCPreferences setTextFieldDataDetectors:automaticDataDetectionEnabled];

	super.automaticDataDetectionEnabled = automaticDataDetectionEnabled;
}

- (void)setAutomaticTextReplacementEnabled:(BOOL)automaticTextReplacementEnabled
{
	[TPCPreferences setTextFieldTextReplacement:automaticTextReplacementEnabled];

	super.automaticTextReplacementEnabled = automaticTextReplacementEnabled;
}

@end

#pragma mark -
#pragma mark Text Field Background Vibrant View

@implementation TVCMainWindowTextViewContentView

- (BOOL)allowsVibrancy
{
	return NO;
}

- (BOOL)isOpaque
{
	/* The view paints nothing; it only hosts the field inside the glass the
	 input bar is placed in. Claiming to be opaque tells AppKit it need not
	 draw what sits behind this view, leaving the glass covered by an undrawn
	 (white) rectangle. */
	return NO;
}

@end

NS_ASSUME_NONNULL_END
