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

#import <UserNotifications/UserNotifications.h>

#import "TLOLocalization.h"
#import "TPCPreferencesLocal.h"
#import "TDCOnboardingSteps.h"

NS_ASSUME_NONNULL_BEGIN

@interface TDCOnboardingNotificationsStepViewController ()
@property(nonatomic, strong) NSButton *highlightCheck;
@property(nonatomic, strong) NSButton *privateMessageCheck;
@property(nonatomic, strong) NSButton *soundsCheck;
@property(nonatomic, strong) NSTextField *permissionField;
@property(nonatomic, strong) NSImageView *permissionImageView;
@end

@implementation TDCOnboardingNotificationsStepViewController

- (NSString *)stepTitle
{
	return TXTLS(@"TDCOnboardingWindow[nt1-tt]");
}

- (NSString *)stepSubtitle
{
	return TXTLS(@"TDCOnboardingWindow[nt1-st]");
}

- (void)loadView
{
	NSView *view = [self makeContentView];

	self.view = view;

	NSButton *highlightCheck = [NSButton checkboxWithTitle:TXTLS(@"TDCOnboardingWindow[nt1-hl]")
													target:self
													action:@selector(checkboxChanged:)];

	NSButton *privateMessageCheck = [NSButton checkboxWithTitle:TXTLS(@"TDCOnboardingWindow[nt1-pm]")
														 target:self
														 action:@selector(checkboxChanged:)];

	NSButton *soundsCheck = [NSButton checkboxWithTitle:TXTLS(@"TDCOnboardingWindow[nt1-sn]")
												 target:self
												 action:@selector(checkboxChanged:)];

	NSStackView *checkStack = [NSStackView stackViewWithViews:@[ highlightCheck, privateMessageCheck, soundsCheck ]];

	checkStack.orientation = NSUserInterfaceLayoutOrientationVertical;
	checkStack.alignment = NSLayoutAttributeLeading;
	checkStack.spacing = 10;
	checkStack.translatesAutoresizingMaskIntoConstraints = NO;

	NSImageView *permissionImageView = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"bell.badge"
																				 accessibilityDescription:nil]];

	permissionImageView.contentTintColor = [NSColor secondaryLabelColor];
	permissionImageView.symbolConfiguration =
		[NSImageSymbolConfiguration configurationWithPointSize:22 weight:NSFontWeightRegular];
	permissionImageView.translatesAutoresizingMaskIntoConstraints = NO;

	NSTextField *permissionField = [NSTextField wrappingLabelWithString:TXTLS(@"TDCOnboardingWindow[nt1-pr]")];

	permissionField.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
	permissionField.textColor = [NSColor secondaryLabelColor];
	permissionField.translatesAutoresizingMaskIntoConstraints = NO;

	[view addSubview:checkStack];
	[view addSubview:permissionImageView];
	[view addSubview:permissionField];

	NSLayoutGuide *form = [NSLayoutGuide new];

	[view addLayoutGuide:form];

	[NSLayoutConstraint activateConstraints:@[
		[form.widthAnchor constraintEqualToConstant:420],
		[form.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
		[form.topAnchor constraintEqualToAnchor:view.topAnchor constant:24],

		[checkStack.topAnchor constraintEqualToAnchor:form.topAnchor],
		[checkStack.leadingAnchor constraintEqualToAnchor:form.leadingAnchor],
		[checkStack.trailingAnchor constraintLessThanOrEqualToAnchor:form.trailingAnchor],

		[permissionImageView.topAnchor constraintEqualToAnchor:checkStack.bottomAnchor constant:32],
		[permissionImageView.leadingAnchor constraintEqualToAnchor:form.leadingAnchor],
		[permissionImageView.widthAnchor constraintEqualToConstant:28],

		[permissionField.leadingAnchor constraintEqualToAnchor:permissionImageView.trailingAnchor constant:10],
		[permissionField.trailingAnchor constraintEqualToAnchor:form.trailingAnchor],
		[permissionField.topAnchor constraintEqualToAnchor:permissionImageView.topAnchor],
	]];

	self.highlightCheck = highlightCheck;
	self.privateMessageCheck = privateMessageCheck;
	self.soundsCheck = soundsCheck;
	self.permissionField = permissionField;
	self.permissionImageView = permissionImageView;
}

- (void)stepWillAppear
{
	TDCOnboardingSettings *settings = self.settings;

	self.highlightCheck.state = (settings.notifyOnHighlight ? NSControlStateValueOn : NSControlStateValueOff);
	self.privateMessageCheck.state = (settings.notifyOnPrivateMessage ? NSControlStateValueOn : NSControlStateValueOff);
	self.soundsCheck.state = (settings.playSounds ? NSControlStateValueOn : NSControlStateValueOff);

	[self refreshPermissionStatus];
}

/* When macOS has already decided, say so instead of promising a prompt. */
- (void)refreshPermissionStatus
{
	__weak typeof(self) weakSelf = self;

	[RZUserNotificationCenter() getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
		NSString *message = nil;

		switch (settings.authorizationStatus) {
		case UNAuthorizationStatusAuthorized:
		case UNAuthorizationStatusProvisional: {
			message = TXTLS(@"TDCOnboardingWindow[nt1-pd]");

			break;
		}
		case UNAuthorizationStatusDenied: {
			message = TXTLS(@"TDCOnboardingWindow[nt1-pn]");

			break;
		}
		default: {
			message = TXTLS(@"TDCOnboardingWindow[nt1-pr]");

			break;
		}
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			weakSelf.permissionField.stringValue = message;
		});
	}];
}

- (void)checkboxChanged:(NSButton *)sender
{
	TDCOnboardingSettings *settings = self.settings;

	settings.notifyOnHighlight = (self.highlightCheck.state == NSControlStateValueOn);
	settings.notifyOnPrivateMessage = (self.privateMessageCheck.state == NSControlStateValueOn);
	settings.playSounds = (self.soundsCheck.state == NSControlStateValueOn);
}

- (BOOL)commitWithError:(NSString *_Nullable *_Nullable)errorDescription
{
	[self checkboxChanged:self.highlightCheck];

	/* The system prompt appears once; later calls return the stored answer. */
	[RZUserNotificationCenter() requestAuthorizationWithOptions:(UNAuthorizationOptionAlert |
																 UNAuthorizationOptionProvidesAppNotificationSettings)
											  completionHandler:^(BOOL granted, NSError *_Nullable error) {
												  if (error) {
													  LogToConsoleError("Notifications failed to authorize: %{public}@",
																		error.localizedDescription);
												  }
											  }];

	return YES;
}

@end

NS_ASSUME_NONNULL_END
