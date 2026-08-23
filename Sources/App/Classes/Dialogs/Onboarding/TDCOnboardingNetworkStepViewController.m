/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
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

#import "IRCClientConfig.h"
#import "IRCNetworkList.h"
#import "TLOLocalization.h"
#import "TDCNetworkPickerViewController.h"
#import "TDCOnboardingSteps.h"

NS_ASSUME_NONNULL_BEGIN

@interface TDCOnboardingNetworkStepViewController () <TDCNetworkPickerViewControllerDelegate>
@property(nonatomic, strong) TDCNetworkPickerViewController *picker;
@property(nonatomic, strong) NSButton *connectCheck;
@property(nonatomic, strong) NSTextField *channelsLabel;
@property(nonatomic, strong) NSStackView *channelStack;
@property(nonatomic, strong) NSTextField *channelsPlaceholder;
@end

@implementation TDCOnboardingNetworkStepViewController

- (NSString *)stepTitle
{
	return TXTLS(@"TDCOnboardingWindow[nw1-tt]");
}

- (NSString *)stepSubtitle
{
	return TXTLS(@"TDCOnboardingWindow[nw1-st]");
}

- (nullable NSView *)preferredFirstResponder
{
	return nil;
}

- (void)loadView
{
	NSView *view = [self makeContentView];

	self.view = view;

	TDCNetworkPickerViewController *picker = [TDCNetworkPickerViewController new];

	picker.delegate = self;

	[self addChildViewController:picker];

	NSView *pickerView = picker.view;

	NSButton *connectCheck = [NSButton checkboxWithTitle:TXTLS(@"TDCOnboardingWindow[nw1-cn]")
												  target:self
												  action:@selector(connectCheckChanged:)];

	connectCheck.translatesAutoresizingMaskIntoConstraints = NO;

	NSTextField *channelsLabel = [NSTextField labelWithString:TXTLS(@"TDCOnboardingWindow[nw1-ch]")];

	channelsLabel.translatesAutoresizingMaskIntoConstraints = NO;

	NSStackView *channelStack = [NSStackView new];

	channelStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
	channelStack.spacing = 12;
	channelStack.translatesAutoresizingMaskIntoConstraints = NO;

	NSTextField *channelsPlaceholder = [NSTextField labelWithString:TXTLS(@"TDCOnboardingWindow[nw1-ep]")];

	channelsPlaceholder.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
	channelsPlaceholder.textColor = [NSColor secondaryLabelColor];
	channelsPlaceholder.translatesAutoresizingMaskIntoConstraints = NO;

	[view addSubview:pickerView];
	[view addSubview:connectCheck];
	[view addSubview:channelsLabel];
	[view addSubview:channelStack];
	[view addSubview:channelsPlaceholder];

	[NSLayoutConstraint activateConstraints:@[
		[pickerView.topAnchor constraintEqualToAnchor:view.topAnchor],
		[pickerView.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
		[pickerView.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],

		[channelsLabel.topAnchor constraintEqualToAnchor:pickerView.bottomAnchor constant:14],
		[channelsLabel.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
		[channelStack.leadingAnchor constraintEqualToAnchor:channelsLabel.trailingAnchor constant:8],
		[channelStack.centerYAnchor constraintEqualToAnchor:channelsLabel.centerYAnchor],
		[channelStack.trailingAnchor constraintLessThanOrEqualToAnchor:view.trailingAnchor],
		[channelsPlaceholder.leadingAnchor constraintEqualToAnchor:channelsLabel.trailingAnchor constant:8],
		[channelsPlaceholder.centerYAnchor constraintEqualToAnchor:channelsLabel.centerYAnchor],

		[connectCheck.topAnchor constraintEqualToAnchor:channelsLabel.bottomAnchor constant:10],
		[connectCheck.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
		[connectCheck.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
	]];

	self.picker = picker;
	self.connectCheck = connectCheck;
	self.channelsLabel = channelsLabel;
	self.channelStack = channelStack;
	self.channelsPlaceholder = channelsPlaceholder;

	[self rebuildChannelList];
}

- (void)stepWillAppear
{
	TDCOnboardingSettings *settings = self.settings;

	self.picker.defaultNickname = settings.nickname;

	self.connectCheck.state = (settings.connectWhenFinished ? NSControlStateValueOn : NSControlStateValueOff);
}

- (void)connectCheckChanged:(NSButton *)sender
{
	self.settings.connectWhenFinished = (sender.state == NSControlStateValueOn);
}

#pragma mark -
#pragma mark Channels

- (void)rebuildChannelList
{
	NSStackView *stack = self.channelStack;

	for (NSView *view in [stack.arrangedSubviews copy]) {
		[stack removeArrangedSubview:view];

		[view removeFromSuperview];
	}

	NSArray<NSString *> *channels = self.picker.suggestedChannels;

	for (NSString *channel in channels) {
		NSButton *check = [NSButton checkboxWithTitle:channel target:self action:@selector(channelCheckChanged:)];

		check.state = NSControlStateValueOn;

		[stack addArrangedSubview:check];
	}

	self.channelsPlaceholder.hidden = (channels.count > 0);

	[self channelCheckChanged:nil];
}

- (void)channelCheckChanged:(nullable id)sender
{
	NSMutableArray<NSString *> *channels = [NSMutableArray array];

	for (NSButton *check in self.channelStack.arrangedSubviews) {
		if (check.state == NSControlStateValueOn) {
			[channels addObject:check.title];
		}
	}

	self.settings.channelsToJoin = channels;
}

#pragma mark -
#pragma mark Picker Delegate

- (void)networkPickerSelectionDidChange:(TDCNetworkPickerViewController *)sender
{
	[self rebuildChannelList];
}

- (void)networkPickerDidConfirmSelection:(TDCNetworkPickerViewController *)sender
{
	/* Double-clicking a network behaves like pressing the default button. */
	[self.view.window.defaultButtonCell performClick:nil];
}

#pragma mark -
#pragma mark Commit

- (BOOL)commitWithError:(NSString *_Nullable *_Nullable)errorDescription
{
	if (self.picker.hasSelection == NO) {
		/* Nothing picked means no network; the flow still finishes. */
		self.settings.clientConfig = nil;
		self.settings.channelsToJoin = @[];

		return YES;
	}

	NSString *pickerError = nil;

	if ([self.picker validateWithError:&pickerError] == NO) {
		if (errorDescription) {
			*errorDescription = (pickerError ?: TXTLS(@"TDCOnboardingWindow[nw1-er]"));
		}

		return NO;
	}

	self.settings.clientConfig = [self.picker clientConfig];

	[self channelCheckChanged:nil];

	return YES;
}

@end

NS_ASSUME_NONNULL_END
