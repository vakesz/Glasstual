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
#import "TDCReactionPopoverControllerPrivate.h"

NS_ASSUME_NONNULL_BEGIN

@interface TDCReactionPopoverController () <NSPopoverDelegate, NSTextFieldDelegate>
@property(nonatomic, copy, readwrite) NSString *messageIdentifier;
@property(nonatomic, strong, nullable) NSPopover *popover;
@property(nonatomic, strong) NSTextField *emojiField;
@property(nonatomic, strong) NSButton *sendButton;
@end

@implementation TDCReactionPopoverController

- (instancetype)initWithMessageIdentifier:(NSString *)messageIdentifier
{
	NSParameterAssert(messageIdentifier != nil);

	if ((self = [super initWithNibName:nil bundle:nil])) {
		self.messageIdentifier = messageIdentifier;
	}

	return self;
}

- (void)loadView
{
	NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 220.0, 44.0)];

	NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];

	field.translatesAutoresizingMaskIntoConstraints = NO;
	field.placeholderString = TXTLS(@"TXMenuController[rct-ph]");
	field.font = [NSFont systemFontOfSize:16.0];
	field.alignment = NSTextAlignmentCenter;
	field.delegate = self;
	field.bezelStyle = NSTextFieldRoundedBezel;
	field.usesSingleLineMode = YES;

	NSButton *send = [NSButton buttonWithTitle:TXTLS(@"TXMenuController[rct-sd]") target:self action:@selector(send:)];

	send.translatesAutoresizingMaskIntoConstraints = NO;
	send.bezelStyle = NSBezelStyleRounded;
	send.keyEquivalent = @"\r";
	send.enabled = NO;

	[view addSubview:field];
	[view addSubview:send];

	[NSLayoutConstraint activateConstraints:@[
		[field.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:12.0],
		[field.centerYAnchor constraintEqualToAnchor:view.centerYAnchor],
		[field.widthAnchor constraintEqualToConstant:120.0],

		[send.leadingAnchor constraintEqualToAnchor:field.trailingAnchor constant:8.0],
		[send.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-12.0],
		[send.firstBaselineAnchor constraintEqualToAnchor:field.firstBaselineAnchor],

		[view.heightAnchor constraintEqualToConstant:44.0],
	]];

	self.emojiField = field;
	self.sendButton = send;

	self.view = view;
}

- (void)presentRelativeToRect:(NSRect)rect ofView:(NSView *)view
{
	NSParameterAssert(view != nil);

	NSPopover *popover = [NSPopover new];

	popover.behavior = NSPopoverBehaviorTransient;
	popover.contentViewController = self;
	popover.delegate = self;

	self.popover = popover;

	[popover showRelativeToRect:rect ofView:view preferredEdge:NSRectEdgeMaxY];

	[self.view.window makeFirstResponder:self.emojiField];
}

- (void)close
{
	[self.popover close];
}

- (void)popoverDidClose:(NSNotification *)notification
{
	self.popover = nil;
}

/* One emoji: the first grapheme cluster of what was typed. */
- (nullable NSString *)emoji
{
	NSString *value =
		[self.emojiField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

	if (value.length == 0) {
		return nil;
	}

	NSRange first = [value rangeOfComposedCharacterSequenceAtIndex:0];

	return [value substringWithRange:first];
}

- (void)controlTextDidChange:(NSNotification *)notification
{
	self.sendButton.enabled = (self.emoji != nil);
}

- (void)send:(nullable id)sender
{
	NSString *emoji = self.emoji;

	if (emoji == nil) {
		return;
	}

	if (self.completionBlock) {
		self.completionBlock(emoji, self.messageIdentifier);
	}

	[self close];
}

@end

NS_ASSUME_NONNULL_END
