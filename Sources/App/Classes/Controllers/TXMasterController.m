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

#import "BuildConfig.h"

#import "NSObjectHelperPrivate.h"
#import "OELReachability.h"
#import "TDCAlert.h"
#import "TLOEncryptionManagerPrivate.h"
#import "TLOLocalization.h"
#import "TLOSpeechSynthesizerPrivate.h"
#import "THOPluginManagerPrivate.h"
#import "TVCLogControllerHistoricLogFilePrivate.h"
#import "TVCLogControllerInlineMediaServicePrivate.h"
#import "TVCLogControllerOperationQueuePrivate.h"
#import "TVCMainWindowPrivate.h"
#import "IRCChannelPrivate.h"
#import "IRCChannelMemberListPrivate.h"
#import "IRCCommandIndexPrivate.h"
#import "IRCExtrasPrivate.h"
#import "IRCWorldPrivate.h"
#import "TPCApplicationInfoPrivate.h"
#import "TPCPreferencesLocalPrivate.h"
#import "TPCPreferencesUserDefaults.h"
#import "TPCResourceManagerPrivate.h"
#import "TPCThemeControllerPrivate.h"
#import "TXMenuControllerPrivate.h"
#import "TXWindowControllerPrivate.h"
#import "TXMasterControllerPrivate.h"
#import "IRCClient.h"

NS_ASSUME_NONNULL_BEGIN

/* Upper bound on how long termination waits for the historic log to save. */
static const NSTimeInterval _terminationHistoricLogSaveTimeout = 15.0;

@interface TXMasterController ()
@property(nonatomic, strong, readwrite) IRCWorld *world;
@property(nonatomic, assign, readwrite) BOOL debugModeIsOn;
@property(nonatomic, assign, readwrite) BOOL ghostModeIsOn;
@property(nonatomic, assign, readwrite) BOOL applicationIsActive;
@property(nonatomic, assign, readwrite) BOOL applicationIsLaunched;
@property(nonatomic, assign, readwrite) BOOL applicationIsTerminating;
@property(nonatomic, assign, readwrite) BOOL applicationIsChangingActiveState;
@property(nonatomic, assign) BOOL terminateHistoricLogSaveStarted;
@property(nonatomic, strong, readwrite) IBOutlet TVCMainWindow *mainWindow;
@property(nonatomic, weak, readwrite) IBOutlet TXMenuController *menuController;
@end

@implementation TXMasterController

#pragma mark -
#pragma mark Initialization

- (instancetype)init
{
	if ((self = [super init])) {
		[NSObject setGlobalMasterControllerClassReference:self];

		[self prepareInitialState];

		return self;
	}

	return nil;
}

- (void)prepareInitialState
{
	LogToConsoleSetDefaultSubsystemToMainBundle(@"General");

	NSUInteger keyboardKeys = ([NSEvent modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask);

	if ((keyboardKeys & NSEventModifierFlagControl) == NSEventModifierFlagControl) {
		self.debugModeIsOn = YES;

		LogToConsoleInfo("Launching in debug mode");
	}

#if defined(DEBUG)
	self.ghostModeIsOn = YES; // Do not use auto connect during debug
#else
	if ((keyboardKeys & NSEventModifierFlagShift) == NSEventModifierFlagShift) {
		self.ghostModeIsOn = YES;

		LogToConsoleInfo("Launching without auto connecting to the configured servers");
	}
#endif
}

- (void)awakeFromNib
{
	static BOOL _awakeFromNibCalled = NO;

	if (_awakeFromNibCalled == NO) {
		_awakeFromNibCalled = YES;

		[self _awakeFromNib];
	}
}

- (void)_awakeFromNib
{
	/* Initialize preferences */
	[TPCPreferences initPreferences];

	/* Call shared instance to warm it */
	[TXSharedApplication sharedAppearance];

	/* We wait until -awakeFromNib to wake the window so that the menu
	 controller created by the main nib has time to load. */
	[RZMainBundle() loadNibNamed:@"TVCMainWindow" owner:self topLevelObjects:nil];
}

- (void)applicationWakeStepOne
{
	self.world = [IRCWorld new];
}

- (void)applicationWakeStepTwo
{
	[IRCCommandIndex populateCommandIndex];

	[self prepareNetworkReachabilityNotifier];

	[RZWorkspaceNotificationCenter() addObserver:self
										selector:@selector(computerDidWakeUp:)
											name:NSWorkspaceDidWakeNotification
										  object:nil];
	[RZWorkspaceNotificationCenter() addObserver:self
										selector:@selector(computerWillSleep:)
											name:NSWorkspaceWillSleepNotification
										  object:nil];
	[RZWorkspaceNotificationCenter() addObserver:self
										selector:@selector(computerWillPowerOff:)
											name:NSWorkspaceWillPowerOffNotification
										  object:nil];
	[RZWorkspaceNotificationCenter() addObserver:self
										selector:@selector(computerScreenDidWake:)
											name:NSWorkspaceScreensDidWakeNotification
										  object:nil];
	[RZWorkspaceNotificationCenter() addObserver:self
										selector:@selector(computerScreenWillSleep:)
											name:NSWorkspaceScreensDidSleepNotification
										  object:nil];

	[RZNotificationCenter() addObserver:self
							   selector:@selector(pluginsFinishedLoading:)
								   name:THOPluginManagerFinishedLoadingPluginsNotification
								 object:nil];

	[RZAppleEventManager() setEventHandler:self
							   andSelector:@selector(handleURLEvent:withReplyEvent:)
							 forEventClass:kInternetEventClass
								andEventID:kAEGetURL];

	[NSColorPanel setPickerMask:(NSColorPanelRGBModeMask | NSColorPanelGrayModeMask | NSColorPanelColorListModeMask |
								 NSColorPanelWheelModeMask | NSColorPanelCrayonModeMask)];

	[[NSColorPanel sharedColorPanel] setShowsAlpha:YES];

	XRPerformBlockAsynchronouslyOnGlobalQueueWithPriority(
		^{
			[TPCResourceManager copyResourcesToApplicationSupportFolder];
		},
		DISPATCH_QUEUE_PRIORITY_BACKGROUND);

	/* Load plugins last so that -applicationDidFinishLaunching is posted
	 only once they have loaded and everything else has been setup. */
	[sharedPluginManager() loadPlugins];
}

- (void)pluginsFinishedLoading:(NSNotification *)notification
{
	[self applicationDidFinishLaunching];
}

#pragma mark -
#pragma mark Services

- (void)prepareNetworkReachabilityNotifier
{
	OELReachability *notifier = [TXSharedApplication sharedNetworkReachabilityNotifier];

	notifier.reachableBlock = ^(OELReachability *reachability) {
		[self.world noteReachabilityChanged:YES];
	};

	notifier.unreachableBlock = ^(OELReachability *reachability) {
		[self.world noteReachabilityChanged:NO];
	};

	[notifier startNotifier];
}

#pragma mark -
#pragma mark NSApplication Delegate

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
	/* UserNotifications.framework wants delegation set before app has
	 finished launching. A simple access to the singleton will set this
	 for us which we can just do here. */
	LogToConsoleDebug("Preparing notification controller singeton: %@", sharedNotificationController().description);
}

- (void)applicationDidFinishLaunching
{
	self.applicationIsLaunched = YES;

	if ([self.mainWindow reloadLoadingScreen]) {
		[self.world autoConnectAfterWakeup:NO];
	}
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
	self.applicationIsChangingActiveState = YES;
}

- (void)applicationWillBecomeActive:(NSNotification *)notification
{
	self.applicationIsChangingActiveState = YES;
}

- (void)applicationDidResignActive:(NSNotification *)notification
{
	self.applicationIsActive = NO;
	self.applicationIsChangingActiveState = NO;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
	self.applicationIsActive = YES;
	self.applicationIsChangingActiveState = NO;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag
{
	if (self.applicationIsTerminating) {
		return NO;
	}

	[self.mainWindow makeKeyAndOrderFront:nil];

	return YES;
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
	if (self.applicationIsTerminating) {
		return NO;
	}

	[self.mainWindow makeKeyAndOrderFront:nil];

	return YES;
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)sender
{
	/* The main window encodes its selection with secure coding. */
	return YES;
}

#pragma mark -
#pragma mark NSApplication Terminate Procedure

- (NSMenu *)applicationDockMenu:(NSApplication *)sender
{
	return self.menuController.dockMenu;
}

/* Returns YES when termination may begin immediately, NO when it is
 refused outright. When a confirmation is needed the answer is deferred:
 the sheet's completion reports to NSApp and begins termination itself. */
- (NSApplicationTerminateReply)queryTerminate
{
	if (self.applicationIsTerminating) {
		LogToConsoleTerminationProgress("Termination is already in progress");

		return NSTerminateNow;
	}

	if ([TPCPreferences confirmQuit] == NO) {
		return NSTerminateNow;
	}

	BOOL stillConnected = NO;

	for (IRCClient *u in worldController().clientList) {
		if (u.isConnecting || u.isConnected) {
			stillConnected = YES;
		}
	}

	if (stillConnected == NO) {
		return NSTerminateNow;
	}

	__weak TXMasterController *weakSelf = self;

	[TDCAlert alertSheetWithWindow:self.mainWindow
							  body:TXTLS(@"Prompts[77u-vp]")
							 title:TXTLS(@"Prompts[6vj-2p]")
					 defaultButton:TXTLS(@"Prompts[1bf-k0]")
				   alternateButton:TXTLS(@"Prompts[qso-2g]")
					   otherButton:nil
				   completionBlock:^(TDCAlertResponse buttonClicked, BOOL suppressed, id _Nullable underlyingAlert) {
					   BOOL result = (buttonClicked == TDCAlertResponseDefault);

					   LogToConsoleTerminationProgress("Perform termination: %{BOOL}d", result);

					   if (result == NO) {
						   [NSApp replyToApplicationShouldTerminate:NO];

						   return;
					   }

					   [weakSelf performApplicationTerminationStepOne];
				   }];

	return NSTerminateLater;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
	NSApplicationTerminateReply reply = [self queryTerminate];

	if (reply != NSTerminateNow) {
		return reply;
	}

	XRPerformBlockAsynchronouslyOnMainQueue(^{
		[self performApplicationTerminationStepOne];
	});

	return NSTerminateLater;
}

/* Clients decrement this as they finish disconnecting (see
 -[IRCClient prepareForApplicationTerminationPostflight]). Once the
 last one is done, the historic log is given its chance to save and
 termination proceeds from its completion. */
- (void)setTerminatingClientCount:(NSUInteger)terminatingClientCount
{
	self->_terminatingClientCount = terminatingClientCount;

	if (terminatingClientCount != 0 || self.applicationIsTerminating == NO) {
		return;
	}

	XRPerformBlockAsynchronouslyOnMainQueue(^{
		[self terminatingClientsDidFinish];
	});
}

- (void)terminatingClientsDidFinish
{
	if (self.applicationIsTerminating == NO || self.terminateHistoricLogSaveStarted) {
		return;
	}

	self.terminateHistoricLogSaveStarted = YES;

	LogToConsoleTerminationProgress("All clients finished; saving historic log");

	__weak TXMasterController *weakSelf = self;

	__block BOOL stepThreePerformed = NO;

	void (^performStepThree)(void) = ^{
		if (stepThreePerformed) {
			return;
		}

		stepThreePerformed = YES;

		[weakSelf performApplicationTerminationStepThree];
	};

	[TVCLogControllerHistoricLogSharedInstance() prepareForApplicationTerminationWithCompletionBlock:performStepThree];

	/* Safety net: should the historic log service never answer, do not
	 leave the application hanging in NSTerminateLater forever. */
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_terminationHistoricLogSaveTimeout * NSEC_PER_SEC)),
				   dispatch_get_main_queue(),
				   ^{
					   if (stepThreePerformed == NO) {
						   LogToConsoleTerminationProgress("Historic log save timed out; terminating anyway");
					   }

					   performStepThree();
				   });
}

- (void)performApplicationTerminationStepOne
{
	LogToConsoleTerminationProgress("Step one entry");

	self.applicationIsTerminating = YES;

	[[TXSharedApplication sharedAppearance] prepareForApplicationTermination];

	[self.mainWindow prepareForApplicationTermination];

	LogToConsoleTerminationProgress("Giving up shared application delegation");

	[[NSApplication sharedApplication] setDelegate:nil];

	LogToConsoleTerminationProgress("Removing workspace notification center observer");

	[RZWorkspaceNotificationCenter() removeObserver:self];

	LogToConsoleTerminationProgress("Removing shared notification center observer");

	[RZNotificationCenter() removeObserver:self];

	LogToConsoleTerminationProgress("Removing AppleScript event observer");

	[RZAppleEventManager() removeEventHandlerForEventClass:kInternetEventClass andEventID:kAEGetURL];

	LogToConsoleTerminationProgress("Stopping reachability notifier");

	[[TXSharedApplication sharedNetworkReachabilityNotifier] stopNotifier];

	LogToConsoleTerminationProgress("Stopping speech synthesizer");

	[[TXSharedApplication sharedSpeechSynthesizer] setIsStopped:YES];

	[TVCLogControllerInlineMediaSharedInstance() prepareForApplicationTermination];

#if GLASSTUAL_BUILT_WITH_ADVANCED_ENCRYPTION == 1
	[sharedEncryptionManager() prepareForApplicationTermination];
#endif

	[self.menuController prepareForApplicationTermination];

	[self performApplicationTerminationStepTwo];
}

- (void)performApplicationTerminationStepTwo
{
	if (self.applicationIsTerminating == NO) {
		return;
	}

	LogToConsoleTerminationProgress("Step two entry");

	/* We want certain things to 100% happen before the app completely closes.
	 Notable actions: gracefully leaving IRC, saving historic logs, etc.
	 Each client decrements -terminatingClientCount once it has finished and
	 the setter continues with step three once the count reaches zero and the
	 historic log has been saved. With no clients, assigning zero here
	 continues immediately. */
	self.terminatingClientCount = worldController().clientCount;

	[self.world prepareForApplicationTermination];
}

- (void)performApplicationTerminationStepThree
{
	if (self.applicationIsTerminating == NO) {
		return;
	}

	LogToConsoleTerminationProgress("Step three entry");

	if (self.skipTerminateSave == NO) {
		LogToConsoleTerminationProgress("Saving IRC world");

		[self.world save];
	}

	LogToConsoleTerminationProgress("Suspending member list dispatch queue");

	[IRCChannelMemberList suspendMemberListSerialQueues];

	LogToConsoleTerminationProgress("Unloading plugins");

	[sharedPluginManager() unloadPlugins];

	[windowController() prepareForApplicationTermination];

	[themeController() prepareForApplicationTermination];

	LogToConsoleTerminationProgress("Saving running internal");

	[TPCApplicationInfo saveTimeIntervalSinceApplicationInstall];

	LogToConsoleTerminationProgress("Terminate");

	[NSApp replyToApplicationShouldTerminate:YES];
}

- (void)terminateGracefully
{
	self.applicationIsTerminating = YES;

	[RZSharedApplication() terminate:nil];
}

#pragma mark -
#pragma mark NSWorkspace Notifications

- (void)handleURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent
{
	NSAppleEventDescriptor *description = [event descriptorAtIndex:1];

	NSString *stringValue = description.stringValue;

	[IRCExtras parseIRCProtocolURI:stringValue withDescriptor:event];
}

- (void)computerScreenWillSleep:(NSNotification *)note
{
	LogToConsole("Preparing for screen sleep");

	[self.world prepareForScreenSleep];
}

- (void)computerScreenDidWake:(NSNotification *)note
{
	LogToConsole("Waking from screen sleep");

	[self.world wakeFromScreenSleep];
}

- (void)computerWillSleep:(NSNotification *)note
{
	LogToConsole("Preparing for sleep");

	[self.world prepareForSleep];

	[[TXSharedApplication sharedSpeechSynthesizer] setIsStopped:YES];
	[[TXSharedApplication sharedSpeechSynthesizer] clearQueue];

	[[TXSharedApplication sharedNetworkReachabilityNotifier] stopNotifier];
}

- (void)computerDidWakeUp:(NSNotification *)note
{
	LogToConsole("Waking from sleep");

	[[TXSharedApplication sharedSpeechSynthesizer] setIsStopped:NO];

	[[TXSharedApplication sharedNetworkReachabilityNotifier] startNotifier];

	[self.world autoConnectAfterWakeup:YES];
}

- (void)computerWillPowerOff:(NSNotification *)note
{
	[self terminateGracefully];
}

@end

NS_ASSUME_NONNULL_END
