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

#import <QuartzCore/QuartzCore.h>

#import "IRCChannelConfig.h"
#import "IRCClient.h"
#import "IRCClientConfig.h"
#import "IRCClientPrivate.h"
#import "IRCWorld.h"
#import "IRCWorldPrivate.h"
#import "TDCAlert.h"
#import "TLOLocalization.h"
#import "TLONotificationController.h"
#import "TPCPreferencesLocal.h"
#import "TPCPreferencesLocalPrivate.h"
#import "TPCPreferencesReload.h"
#import "TPCPreferencesUserDefaults.h"
#import "TPCTheme.h"
#import "TPCThemeController.h"
#import "TVCMainWindow.h"
#import "TVCMainWindowPrivate.h"
#import "TXMasterController.h"
#import "TDCOnboardingSteps.h"
#import "TDCOnboardingWindowController.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark -
#pragma mark Page Indicator

/* A row of dots; the current page is drawn in the accent colour. */
@interface TDCOnboardingPageIndicatorView : NSView
@property(nonatomic, assign) NSUInteger numberOfPages;
@property(nonatomic, assign) NSUInteger currentPage;
@end

@implementation TDCOnboardingPageIndicatorView

- (void)setNumberOfPages:(NSUInteger)numberOfPages
{
	self->_numberOfPages = numberOfPages;

	self.needsDisplay = YES;
}

- (void)setCurrentPage:(NSUInteger)currentPage
{
	self->_currentPage = currentPage;

	self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect
{
	NSUInteger count = self.numberOfPages;

	if (count == 0) {
		return;
	}

	CGFloat diameter = 7.0;
	CGFloat spacing = 9.0;

	CGFloat totalWidth = ((diameter * count) + (spacing * (count - 1)));

	CGFloat x = NSMidX(self.bounds) - (totalWidth / 2.0);
	CGFloat y = NSMidY(self.bounds) - (diameter / 2.0);

	for (NSUInteger i = 0; i < count; i++) {
		NSBezierPath *dot = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x, y, diameter, diameter)];

		if (i == self.currentPage) {
			[[NSColor controlAccentColor] setFill];
		} else {
			[[NSColor quaternaryLabelColor] setFill];
		}

		[dot fill];

		x += (diameter + spacing);
	}
}

- (BOOL)isAccessibilityElement
{
	return YES;
}

- (nullable NSAccessibilityRole)accessibilityRole
{
	return NSAccessibilityProgressIndicatorRole;
}

- (nullable NSString *)accessibilityLabel
{
	return TXTLS(@"TDCOnboardingWindow[ob1-pg]", (long)(self.currentPage + 1), (long)self.numberOfPages);
}

@end

#pragma mark -
#pragma mark Window Controller

@interface TDCOnboardingWindowController () <NSWindowDelegate>
@property(nonatomic, weak) IBOutlet NSImageView *iconImageView;
@property(nonatomic, weak) IBOutlet NSTextField *titleTextField;
@property(nonatomic, weak) IBOutlet NSTextField *subtitleTextField;
@property(nonatomic, weak) IBOutlet NSView *contentContainerView;
@property(nonatomic, weak) IBOutlet NSView *pageIndicatorView;
@property(nonatomic, weak) IBOutlet NSButton *skipButton;
@property(nonatomic, weak) IBOutlet NSButton *backButton;
@property(nonatomic, weak) IBOutlet NSButton *continueButton;
@property(nonatomic, strong) TDCOnboardingPageIndicatorView *pageIndicator;
@property(nonatomic, strong) TDCOnboardingSettings *settings;
@property(nonatomic, copy) NSArray<TDCOnboardingStepViewController *> *steps;
@property(nonatomic, assign) NSUInteger currentStepIndex;
@property(nonatomic, assign) BOOL finished;
@property(nonatomic, assign) BOOL transitioning;
@end

@implementation TDCOnboardingWindowController

+ (BOOL)shouldPresentOnLaunch
{
	if ([TPCPreferences onboardingCompleted]) {
		return NO;
	}

	return (worldController().clientCount == 0);
}

- (instancetype)init
{
	if ((self = [super initWithWindowNibName:@"TDCOnboardingWindow"])) {
		[self prepareInitialState];

		return self;
	}

	return nil;
}

- (void)prepareInitialState
{
	TDCOnboardingSettings *settings = [TDCOnboardingSettings new];

	settings.textSize = [TDCOnboardingSettings textSizeForFontSize:[TPCPreferences themeChannelViewFontSize]];
	settings.appearance = [TPCPreferences appearance];

	self.settings = settings;

	self.steps = @[
		[[TDCOnboardingIdentityStepViewController alloc] initWithSettings:settings],
		[[TDCOnboardingAppearanceStepViewController alloc] initWithSettings:settings],
		[[TDCOnboardingNotificationsStepViewController alloc] initWithSettings:settings],
		[[TDCOnboardingNetworkStepViewController alloc] initWithSettings:settings],
	];
}

- (void)windowDidLoad
{
	[super windowDidLoad];

	NSWindow *window = self.window;

	window.title = TXTLS(@"TDCOnboardingWindow[ob1-wt]");
	window.styleMask |= NSWindowStyleMaskFullSizeContentView;
	window.titlebarAppearsTransparent = YES;
	window.titleVisibility = NSWindowTitleHidden;

	self.iconImageView.image = [NSApp applicationIconImage];

	self.subtitleTextField.maximumNumberOfLines = 2;
	self.subtitleTextField.preferredMaxLayoutWidth = 560;

	self.skipButton.title = TXTLS(@"TDCOnboardingWindow[ob1-sk]");
	self.backButton.title = TXTLS(@"TDCOnboardingWindow[ob1-bk]");

	/* The skip control reads as a link, not a push button, so that the
	 primary action stays the only prominent button on the page. */
	self.skipButton.bordered = NO;
	self.skipButton.contentTintColor = [NSColor linkColor];

	TDCOnboardingPageIndicatorView *pageIndicator =
		[[TDCOnboardingPageIndicatorView alloc] initWithFrame:self.pageIndicatorView.bounds];

	pageIndicator.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
	pageIndicator.numberOfPages = self.steps.count;

	[self.pageIndicatorView addSubview:pageIndicator];

	self.pageIndicator = pageIndicator;

	[self showStepAtIndex:0 animated:NO];
}

- (void)show
{
	NSWindow *window = self.window; // Loads the nib

	[window center];

	[self showWindow:nil];

	[window makeKeyAndOrderFront:nil];
}

#pragma mark -
#pragma mark Steps

- (TDCOnboardingStepViewController *)currentStep
{
	return self.steps[self.currentStepIndex];
}

- (void)showStepAtIndex:(NSUInteger)index animated:(BOOL)animated
{
	NSParameterAssert(index < self.steps.count);

	TDCOnboardingStepViewController *outgoing =
		((self.contentContainerView.subviews.count > 0) ? self.currentStep : nil);

	TDCOnboardingStepViewController *incoming = self.steps[index];

	self.currentStepIndex = index;

	[incoming stepWillAppear];

	NSView *container = self.contentContainerView;

	NSView *incomingView = incoming.view;

	incomingView.translatesAutoresizingMaskIntoConstraints = NO;

	[container addSubview:incomingView];

	[NSLayoutConstraint activateConstraints:@[
		[incomingView.topAnchor constraintEqualToAnchor:container.topAnchor],
		[incomingView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
		[incomingView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
		[incomingView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
	]];

	[self updateChromeForStep:incoming];

	NSView *outgoingView = outgoing.view;

	if (animated == NO || outgoingView == nil || outgoingView == incomingView) {
		if (outgoingView != incomingView) {
			[outgoingView removeFromSuperview];
		}

		[self focusStep:incoming];

		return;
	}

	self.transitioning = YES;

	incomingView.alphaValue = 0.0;

	[NSAnimationContext
		runAnimationGroup:^(NSAnimationContext *context) {
			context.duration = 0.2;
			context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];

			outgoingView.animator.alphaValue = 0.0;
			incomingView.animator.alphaValue = 1.0;
		}
		completionHandler:^{
			[outgoingView removeFromSuperview];

			outgoingView.alphaValue = 1.0;

			self.transitioning = NO;

			[self focusStep:incoming];
		}];
}

- (void)focusStep:(TDCOnboardingStepViewController *)step
{
	NSView *responder = step.preferredFirstResponder;

	if (responder) {
		[self.window makeFirstResponder:responder];
	}
}

- (void)updateChromeForStep:(TDCOnboardingStepViewController *)step
{
	self.titleTextField.stringValue = step.stepTitle;
	self.subtitleTextField.stringValue = step.stepSubtitle;

	BOOL isFirst = (self.currentStepIndex == 0);
	BOOL isLast = (self.currentStepIndex == (self.steps.count - 1));

	self.backButton.hidden = isFirst;
	self.skipButton.hidden = (step.skippable == NO);

	self.continueButton.title =
		(isLast ? TXTLS(@"TDCOnboardingWindow[ob1-fn]") : TXTLS(@"TDCOnboardingWindow[ob1-ct]"));

	self.pageIndicator.currentPage = self.currentStepIndex;
}

#pragma mark -
#pragma mark Actions

- (void)back:(nullable id)sender
{
	if (self.transitioning || self.currentStepIndex == 0) {
		return;
	}

	[self showStepAtIndex:(self.currentStepIndex - 1) animated:YES];
}

- (void)continueToNextStep:(nullable id)sender
{
	if (self.transitioning) {
		return;
	}

	/* Commit any field still being edited. */
	[self.window makeFirstResponder:nil];

	NSString *errorDescription = nil;

	if ([self.currentStep commitWithError:&errorDescription] == NO) {
		if (errorDescription.length > 0) {
			[TDCAlert alertSheetWithWindow:self.window
									  body:errorDescription
									 title:self.currentStep.stepTitle
							 defaultButton:TXTLS(@"Prompts[c7s-dq]")
						   alternateButton:nil
							   otherButton:nil];
		}

		[self focusStep:self.currentStep];

		return;
	}

	NSUInteger nextIndex = (self.currentStepIndex + 1);

	if (nextIndex < self.steps.count) {
		[self showStepAtIndex:nextIndex animated:YES];

		return;
	}

	[self finish];
}

- (void)skip:(nullable id)sender
{
	[self closeAsCompleted];
}

- (void)cancel:(nullable id)sender
{
	[self skip:sender];
}

- (void)cancelOperation:(nullable id)sender
{
	[self skip:sender];
}

#pragma mark -
#pragma mark Finishing

- (void)closeAsCompleted
{
	[TPCPreferences setOnboardingCompleted:YES];

	[self close];
}

- (void)finish
{
	if (self.finished) {
		return;
	}

	self.finished = YES;

	[self applyIdentitySettings];
	[self applyAppearanceSettings];
	[self applyNotificationSettings];
	[self createClient];

	[self closeAsCompleted];
}

- (void)applyIdentitySettings
{
	TDCOnboardingSettings *settings = self.settings;

	if (settings.nickname.length > 0) {
		[RZUserDefaults() setObject:settings.nickname forKey:@"DefaultIdentity -> Nickname"];
	}

	if (settings.realName.length > 0) {
		[RZUserDefaults() setObject:settings.realName forKey:@"DefaultIdentity -> Realname"];
	}
}

- (void)applyAppearanceSettings
{
	TDCOnboardingSettings *settings = self.settings;

	TPCPreferencesReloadAction reloadAction = 0;

	/* The bundled chat styles are looked up by name. When a style is not
	 shipped in this build the current theme is left alone. */
	NSString *themeName = [TPCThemeController buildFilename:settings.styleName
										 forStorageLocation:TPCThemeStorageLocationBundle];

	if (themeName && [themeController() themeExists:themeName]) {
		if ([[TPCPreferences themeName] isEqualToString:themeName] == NO) {
			[TPCPreferences setThemeName:themeName];

			reloadAction |= TPCPreferencesReloadActionStyle;
		}
	} else {
		LogToConsoleInfo("Chat style '%{public}@' is not bundled; keeping the current theme", settings.styleName);
	}

	CGFloat fontSize = [TDCOnboardingSettings fontSizeForTextSize:settings.textSize];

	if ([TPCPreferences themeChannelViewFontSize] != fontSize) {
		[TPCPreferences setThemeChannelViewFontSize:fontSize];

		reloadAction |= TPCPreferencesReloadActionStyle;
	}

	if ([TPCPreferences appearance] != settings.appearance) {
		[TPCPreferences setAppearance:settings.appearance];

		reloadAction |= TPCPreferencesReloadActionAppearance;
	}

	if (reloadAction != 0) {
		[TPCPreferences performReloadAction:reloadAction];
	}
}

- (void)applyNotificationSettings
{
	TDCOnboardingSettings *settings = self.settings;

	[TPCPreferences setNotificationEnabled:settings.notifyOnHighlight forEvent:TXNotificationTypeHighlight];
	[TPCPreferences setNotificationEnabled:settings.notifyOnPrivateMessage forEvent:TXNotificationTypePrivateMessage];
	[TPCPreferences setNotificationEnabled:settings.notifyOnPrivateMessage
								  forEvent:TXNotificationTypeNewPrivateMessage];

	[TPCPreferences setSoundIsMuted:(settings.playSounds == NO)];
}

- (void)createClient
{
	TDCOnboardingSettings *settings = self.settings;

	IRCClientConfigMutable *config = settings.clientConfig;

	if (config == nil) {
		return;
	}

	config.nickname = settings.nickname;

	if (settings.realName.length > 0) {
		config.realName = settings.realName;
	}

	if (settings.alternateNickname.length > 0) {
		config.alternateNicknames = @[ settings.alternateNickname ];
	}

	config.autoConnect = settings.connectWhenFinished;

	NSMutableArray<IRCChannelConfig *> *channelList = [NSMutableArray array];

	for (NSString *channelName in settings.channelsToJoin) {
		[channelList addObject:[IRCChannelConfig seedWithName:channelName]];
	}

	config.channelList = channelList;

	/* -initWithConfig: moves the account password into the keychain. */
	IRCClient *client = [worldController() createClientWithConfig:[config copy] reload:YES];

	[mainWindow() expandClient:client];

	[worldController() save];

	[mainWindow() reloadLoadingScreen];

	if (settings.connectWhenFinished) {
		[client connect];
	}

	[client selectFirstChannelInChannelList];
}

#pragma mark -
#pragma mark Window Delegate

- (BOOL)windowShouldClose:(NSWindow *)sender
{
	/* Closing the window is the same as skipping the rest of the flow. */
	[TPCPreferences setOnboardingCompleted:YES];

	return YES;
}

- (void)windowWillClose:(NSNotification *)note
{
	if ([self.delegate respondsToSelector:@selector(onboardingWindowControllerWillClose:)]) {
		[self.delegate onboardingWindowControllerWillClose:self];
	}
}

@end

NS_ASSUME_NONNULL_END
