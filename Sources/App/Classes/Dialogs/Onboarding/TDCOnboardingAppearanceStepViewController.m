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

#import "TLOLocalization.h"
#import "TPCPreferencesLocal.h"
#import "TDCOnboardingSteps.h"

NS_ASSUME_NONNULL_BEGIN

@interface TDCOnboardingAppearanceStepViewController ()
@property(nonatomic, strong) TDCOnboardingStylePreviewView *bubblesPreview;
@property(nonatomic, strong) TDCOnboardingStylePreviewView *linesPreview;
@property(nonatomic, strong) NSSegmentedControl *textSizeControl;
@property(nonatomic, strong) NSSegmentedControl *appearanceControl;
@end

@implementation TDCOnboardingAppearanceStepViewController

- (NSString *)stepTitle
{
	return TXTLS(@"TDCOnboardingWindow[lf1-tt]");
}

- (NSString *)stepSubtitle
{
	return TXTLS(@"TDCOnboardingWindow[lf1-st]");
}

- (void)loadView
{
	NSView *view = [self makeContentView];

	self.view = view;

	TDCOnboardingStylePreviewView *bubblesPreview = [TDCOnboardingStylePreviewView new];

	bubblesPreview.styleName = @"Bubbles";
	bubblesPreview.styleTitle = TXTLS(@"TDCOnboardingWindow[lf1-bb]");
	bubblesPreview.styleDescription = TXTLS(@"TDCOnboardingWindow[lf1-bd]");
	bubblesPreview.target = self;
	bubblesPreview.action = @selector(previewSelected:);
	bubblesPreview.translatesAutoresizingMaskIntoConstraints = NO;

	TDCOnboardingStylePreviewView *linesPreview = [TDCOnboardingStylePreviewView new];

	linesPreview.styleName = @"Lines";
	linesPreview.styleTitle = TXTLS(@"TDCOnboardingWindow[lf1-ln]");
	linesPreview.styleDescription = TXTLS(@"TDCOnboardingWindow[lf1-ld]");
	linesPreview.target = self;
	linesPreview.action = @selector(previewSelected:);
	linesPreview.translatesAutoresizingMaskIntoConstraints = NO;

	NSStackView *previewStack = [NSStackView stackViewWithViews:@[ bubblesPreview, linesPreview ]];

	previewStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
	previewStack.distribution = NSStackViewDistributionFillEqually;
	previewStack.spacing = 20;
	previewStack.translatesAutoresizingMaskIntoConstraints = NO;
	previewStack.accessibilityLabel = TXTLS(@"TDCOnboardingWindow[lf1-ax]");

	NSTextField *textSizeLabel = [NSTextField labelWithString:TXTLS(@"TDCOnboardingWindow[lf1-fs]")];

	textSizeLabel.alignment = NSTextAlignmentRight;
	textSizeLabel.translatesAutoresizingMaskIntoConstraints = NO;

	NSSegmentedControl *textSizeControl =
		[NSSegmentedControl segmentedControlWithLabels:@[
			TXTLS(@"TDCOnboardingWindow[lf1-s1]"),
			TXTLS(@"TDCOnboardingWindow[lf1-s2]"),
			TXTLS(@"TDCOnboardingWindow[lf1-s3]")
		]
										  trackingMode:NSSegmentSwitchTrackingSelectOne
												target:self
												action:@selector(textSizeChanged:)];

	textSizeControl.translatesAutoresizingMaskIntoConstraints = NO;

	NSTextField *appearanceLabel = [NSTextField labelWithString:TXTLS(@"TDCOnboardingWindow[lf1-ap]")];

	appearanceLabel.alignment = NSTextAlignmentRight;
	appearanceLabel.translatesAutoresizingMaskIntoConstraints = NO;

	NSSegmentedControl *appearanceControl =
		[NSSegmentedControl segmentedControlWithLabels:@[
			TXTLS(@"TDCOnboardingWindow[lf1-a1]"),
			TXTLS(@"TDCOnboardingWindow[lf1-a2]"),
			TXTLS(@"TDCOnboardingWindow[lf1-a3]")
		]
										  trackingMode:NSSegmentSwitchTrackingSelectOne
												target:self
												action:@selector(appearanceChanged:)];

	appearanceControl.translatesAutoresizingMaskIntoConstraints = NO;

	[view addSubview:previewStack];
	[view addSubview:textSizeLabel];
	[view addSubview:textSizeControl];
	[view addSubview:appearanceLabel];
	[view addSubview:appearanceControl];

	[NSLayoutConstraint activateConstraints:@[
		[previewStack.topAnchor constraintEqualToAnchor:view.topAnchor constant:8],
		[previewStack.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20],
		[previewStack.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-20],

		[textSizeControl.topAnchor constraintEqualToAnchor:previewStack.bottomAnchor constant:24],
		[textSizeControl.centerXAnchor constraintEqualToAnchor:view.centerXAnchor constant:60],
		[textSizeLabel.trailingAnchor constraintEqualToAnchor:textSizeControl.leadingAnchor constant:-8],
		[textSizeLabel.centerYAnchor constraintEqualToAnchor:textSizeControl.centerYAnchor],

		[appearanceControl.topAnchor constraintEqualToAnchor:textSizeControl.bottomAnchor constant:12],
		[appearanceControl.leadingAnchor constraintEqualToAnchor:textSizeControl.leadingAnchor],
		[appearanceLabel.trailingAnchor constraintEqualToAnchor:textSizeLabel.trailingAnchor],
		[appearanceLabel.centerYAnchor constraintEqualToAnchor:appearanceControl.centerYAnchor],
	]];

	self.bubblesPreview = bubblesPreview;
	self.linesPreview = linesPreview;
	self.textSizeControl = textSizeControl;
	self.appearanceControl = appearanceControl;
}

- (void)stepWillAppear
{
	TDCOnboardingSettings *settings = self.settings;

	[self updatePreviewSelection];

	self.textSizeControl.selectedSegment = settings.textSize;

	CGFloat fontSize = [TDCOnboardingSettings fontSizeForTextSize:settings.textSize];

	self.bubblesPreview.messageFontSize = fontSize;
	self.linesPreview.messageFontSize = fontSize;

	self.appearanceControl.selectedSegment = settings.appearance;
}

- (void)updatePreviewSelection
{
	BOOL bubbles = [self.settings.styleName isEqualToString:@"Bubbles"];

	self.bubblesPreview.selected = bubbles;
	self.linesPreview.selected = (bubbles == NO);
}

- (void)previewSelected:(TDCOnboardingStylePreviewView *)sender
{
	self.settings.styleName = sender.styleName;

	[self updatePreviewSelection];
}

- (void)textSizeChanged:(NSSegmentedControl *)sender
{
	TDCOnboardingTextSize textSize = (TDCOnboardingTextSize)sender.selectedSegment;

	self.settings.textSize = textSize;

	CGFloat fontSize = [TDCOnboardingSettings fontSizeForTextSize:textSize];

	self.bubblesPreview.messageFontSize = fontSize;
	self.linesPreview.messageFontSize = fontSize;
}

- (void)appearanceChanged:(NSSegmentedControl *)sender
{
	self.settings.appearance = (TXPreferredAppearance)sender.selectedSegment;
}

@end

NS_ASSUME_NONNULL_END
