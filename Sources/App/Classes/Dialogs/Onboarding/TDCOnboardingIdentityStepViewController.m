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

#import "NSStringHelper.h"
#import "TLOLocalization.h"
#import "TPCPreferencesLocal.h"
#import "TVCValidatedTextField.h"
#import "TDCOnboardingSteps.h"

NS_ASSUME_NONNULL_BEGIN

@interface TDCOnboardingIdentityStepViewController () <NSTextFieldDelegate>
@property(nonatomic, strong) TVCValidatedTextField *nicknameField;
@property(nonatomic, strong) NSTextField *realNameField;
@property(nonatomic, strong) TVCValidatedTextField *alternateNicknameField;
@end

@implementation TDCOnboardingIdentityStepViewController

- (NSString *)stepTitle
{
	return TXTLS(@"TDCOnboardingWindow[id1-tt]");
}

- (NSString *)stepSubtitle
{
	return TXTLS(@"TDCOnboardingWindow[id1-st]");
}

- (BOOL)skippable
{
	return NO;
}

- (nullable NSView *)preferredFirstResponder
{
	return self.nicknameField;
}

- (NSTextField *)makeLabel:(NSString *)title
{
	NSTextField *label = [NSTextField labelWithString:title];

	label.alignment = NSTextAlignmentRight;
	label.translatesAutoresizingMaskIntoConstraints = NO;

	return label;
}

- (void)loadView
{
	NSView *view = [self makeContentView];

	self.view = view;

	NSTextField *nicknameLabel = [self makeLabel:TXTLS(@"TDCOnboardingWindow[id1-nk]")];

	TVCValidatedTextField *nicknameField = [TVCValidatedTextField new];

	nicknameField.placeholderString = TXTLS(@"TDCOnboardingWindow[id1-np]");
	nicknameField.stringValueIsInvalidOnEmpty = YES;
	nicknameField.stringValueIsTrimmed = YES;
	nicknameField.stringValueUsesOnlyFirstToken = YES;
	nicknameField.translatesAutoresizingMaskIntoConstraints = NO;

	nicknameField.validationBlock = ^NSString *_Nullable(NSString *currentValue)
	{
		if (currentValue.isHostmaskNickname == NO) {
			return TXTLS(@"CommonErrors[och-j5]");
		}

		return nil;
	};

	NSTextField *realNameLabel = [self makeLabel:TXTLS(@"TDCOnboardingWindow[id1-rn]")];

	NSTextField *realNameField = [NSTextField textFieldWithString:@""];

	realNameField.placeholderString = TXTLS(@"TDCOnboardingWindow[id1-rp]");
	realNameField.translatesAutoresizingMaskIntoConstraints = NO;

	NSTextField *alternateLabel = [self makeLabel:TXTLS(@"TDCOnboardingWindow[id1-an]")];

	TVCValidatedTextField *alternateField = [TVCValidatedTextField new];

	alternateField.placeholderString = TXTLS(@"TDCOnboardingWindow[id1-ap]");
	alternateField.stringValueIsInvalidOnEmpty = NO;
	alternateField.stringValueIsTrimmed = YES;
	alternateField.stringValueUsesOnlyFirstToken = YES;
	alternateField.translatesAutoresizingMaskIntoConstraints = NO;

	alternateField.validationBlock = ^NSString *_Nullable(NSString *currentValue)
	{
		if (currentValue.length > 0 && currentValue.isHostmaskNickname == NO) {
			return TXTLS(@"CommonErrors[och-j5]");
		}

		return nil;
	};

	NSTextField *alternateHelp = [NSTextField wrappingLabelWithString:TXTLS(@"TDCOnboardingWindow[id1-ah]")];

	alternateHelp.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
	alternateHelp.textColor = [NSColor secondaryLabelColor];
	alternateHelp.translatesAutoresizingMaskIntoConstraints = NO;

	[view addSubview:nicknameLabel];
	[view addSubview:nicknameField];
	[view addSubview:realNameLabel];
	[view addSubview:realNameField];
	[view addSubview:alternateLabel];
	[view addSubview:alternateField];
	[view addSubview:alternateHelp];

	/* The form is centred in the content area with a fixed width, the way
	 the Setup Assistant lays out its short forms. */
	NSLayoutGuide *form = [NSLayoutGuide new];

	[view addLayoutGuide:form];

	[NSLayoutConstraint activateConstraints:@[
		[form.widthAnchor constraintEqualToConstant:440],
		[form.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
		[form.topAnchor constraintEqualToAnchor:view.topAnchor constant:24],

		[nicknameLabel.topAnchor constraintEqualToAnchor:form.topAnchor],
		[nicknameLabel.leadingAnchor constraintEqualToAnchor:form.leadingAnchor],
		[nicknameLabel.widthAnchor constraintEqualToConstant:140],
		[nicknameField.leadingAnchor constraintEqualToAnchor:nicknameLabel.trailingAnchor constant:8],
		[nicknameField.trailingAnchor constraintEqualToAnchor:form.trailingAnchor],
		[nicknameField.firstBaselineAnchor constraintEqualToAnchor:nicknameLabel.firstBaselineAnchor],

		[realNameLabel.topAnchor constraintEqualToAnchor:nicknameField.bottomAnchor constant:12],
		[realNameLabel.trailingAnchor constraintEqualToAnchor:nicknameLabel.trailingAnchor],
		[realNameLabel.widthAnchor constraintEqualToAnchor:nicknameLabel.widthAnchor],
		[realNameField.leadingAnchor constraintEqualToAnchor:nicknameField.leadingAnchor],
		[realNameField.trailingAnchor constraintEqualToAnchor:nicknameField.trailingAnchor],
		[realNameField.firstBaselineAnchor constraintEqualToAnchor:realNameLabel.firstBaselineAnchor],

		[alternateLabel.topAnchor constraintEqualToAnchor:realNameField.bottomAnchor constant:12],
		[alternateLabel.trailingAnchor constraintEqualToAnchor:nicknameLabel.trailingAnchor],
		[alternateLabel.widthAnchor constraintEqualToAnchor:nicknameLabel.widthAnchor],
		[alternateField.leadingAnchor constraintEqualToAnchor:nicknameField.leadingAnchor],
		[alternateField.trailingAnchor constraintEqualToAnchor:nicknameField.trailingAnchor],
		[alternateField.firstBaselineAnchor constraintEqualToAnchor:alternateLabel.firstBaselineAnchor],

		[alternateHelp.topAnchor constraintEqualToAnchor:alternateField.bottomAnchor constant:4],
		[alternateHelp.leadingAnchor constraintEqualToAnchor:nicknameField.leadingAnchor],
		[alternateHelp.trailingAnchor constraintEqualToAnchor:nicknameField.trailingAnchor],
	]];

	self.nicknameField = nicknameField;
	self.realNameField = realNameField;
	self.alternateNicknameField = alternateField;
}

- (void)stepWillAppear
{
	TDCOnboardingSettings *settings = self.settings;

	if (settings.nickname.length == 0) {
		settings.nickname = [TPCPreferences defaultNickname];
	}

	if (settings.realName.length == 0) {
		settings.realName = [TPCPreferences defaultRealName];
	}

	self.nicknameField.stringValue = settings.nickname;
	self.realNameField.stringValue = settings.realName;
	self.alternateNicknameField.stringValue = (settings.alternateNickname ?: @"");
}

- (BOOL)commitWithError:(NSString *_Nullable *_Nullable)errorDescription
{
	[self.nicknameField performValidation];
	[self.alternateNicknameField performValidation];

	if (self.nicknameField.valueIsValid == NO) {
		[self.nicknameField showValidationErrorPopover];

		if (errorDescription) {
			*errorDescription = self.nicknameField.lastValidationErrorDescription;
		}

		return NO;
	}

	if (self.alternateNicknameField.valueIsValid == NO) {
		[self.alternateNicknameField showValidationErrorPopover];

		if (errorDescription) {
			*errorDescription = self.alternateNicknameField.lastValidationErrorDescription;
		}

		return NO;
	}

	TDCOnboardingSettings *settings = self.settings;

	settings.nickname = self.nicknameField.value;
	settings.realName = self.realNameField.stringValue.trim;

	NSString *alternate = self.alternateNicknameField.value;

	settings.alternateNickname = ((alternate.length > 0) ? alternate : nil);

	return YES;
}

@end

NS_ASSUME_NONNULL_END
