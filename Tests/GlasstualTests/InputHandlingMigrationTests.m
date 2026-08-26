/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

#import <XCTest/XCTest.h>

#import "GLTTestClient.h"
#import "IRCChannelPrivate.h"
#import "IRCChannelUserPrivate.h"
#import "IRCUser.h"
#import "TLOInputHistoryPrivate.h"
#import "TLOKeyEventHandler.h"
#import "TLONicknameCompletionStatusPrivate.h"
#import "IRCCommandIndexPrivate.h"
#import "TPCPreferencesUserDefaults.h"
#import "TVCMainWindow.h"
#import "TVCMainWindowTextView.h"

NS_ASSUME_NONNULL_BEGIN

@interface GLTKeyEventTarget : NSObject
@property(nonatomic) NSUInteger invocationCount;
@property(nonatomic, strong, nullable) NSEvent *lastEvent;
@end

@implementation GLTKeyEventTarget

- (void)handleKeyEvent:(NSEvent *)event
{
	self.invocationCount += 1;
	self.lastEvent = event;
}

@end

@interface GLTCompletionWindow : TVCMainWindow
@property(nonatomic, strong) TVCMainWindowTextView *testInputTextField;
@property(nonatomic, strong, nullable) IRCClient *testSelectedClient;
@property(nonatomic, strong, nullable) IRCChannel *testSelectedChannel;
@end

@implementation GLTCompletionWindow

- (nullable TVCMainWindowTextView *)inputTextField
{
	return self.testInputTextField;
}

- (nullable IRCClient *)selectedClient
{
	return self.testSelectedClient;
}

- (nullable IRCChannel *)selectedChannel
{
	return self.testSelectedChannel;
}

@end

@interface GLTCompletionChannel : IRCChannel
@property(nonatomic, copy) NSArray<IRCChannelUser *> *testMembers;
@end

@implementation GLTCompletionChannel

- (nullable NSArray<IRCChannelUser *> *)memberList
{
	return self.testMembers;
}

@end

@interface InputHandlingMigrationTests : XCTestCase
@end

@implementation InputHandlingMigrationTests

- (void)testInputHistoryNavigatesEntriesAndSkipsConsecutiveDuplicates
{
	NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
	BOOL originalChannelSpecificValue = [defaults boolForKey:@"SaveInputHistoryPerSelection"];

	[defaults setBool:NO forKey:@"SaveInputHistoryPerSelection"];

	TVCMainWindow *window = [[TVCMainWindow alloc] initWithContentRect:NSZeroRect
															 styleMask:NSWindowStyleMaskBorderless
															   backing:NSBackingStoreBuffered
																 defer:NO];
	TLOInputHistory *history = [[TLOInputHistory alloc] initWithWindow:window];

	[history add:[[NSAttributedString alloc] initWithString:@"first"]];
	[history add:[[NSAttributedString alloc] initWithString:@"second"]];
	[history add:[[NSAttributedString alloc] initWithString:@"second"]];

	XCTAssertEqualObjects([history up:[[NSAttributedString alloc] initWithString:@""]].string, @"second");
	XCTAssertEqualObjects([history up:[[NSAttributedString alloc] initWithString:@"second"]].string, @"first");
	XCTAssertEqualObjects([history down:[[NSAttributedString alloc] initWithString:@"first"]].string, @"second");
	XCTAssertEqualObjects([history down:[[NSAttributedString alloc] initWithString:@"second"]].string, @"");

	[defaults setBool:originalChannelSpecificValue forKey:@"SaveInputHistoryPerSelection"];
}

- (void)testKeyEventHandlerDispatchesRegisteredKeyCode
{
	GLTKeyEventTarget *target = [GLTKeyEventTarget new];
	TLOKeyEventHandler *handler = [[TLOKeyEventHandler alloc] initWithTarget:target];
	NSEvent *event = [self keyEventWithCharacters:@"a" modifiers:NSEventModifierFlagCommand keyCode:42];

	[handler registerSelector:@selector(handleKeyEvent:) key:42 modifiers:NSEventModifierFlagCommand];

	XCTAssertTrue([handler processKeyEvent:event]);
	XCTAssertEqual(target.invocationCount, 1);
	XCTAssertEqual(target.lastEvent, event);
}

- (void)testKeyEventHandlerFallsBackToCaseInsensitiveCharacter
{
	GLTKeyEventTarget *target = [GLTKeyEventTarget new];
	TLOKeyEventHandler *handler = [[TLOKeyEventHandler alloc] initWithTarget:target];
	NSEvent *event = [self keyEventWithCharacters:@"A" modifiers:0 keyCode:42];

	[handler registerSelector:@selector(handleKeyEvent:) character:'a' modifiers:0];

	XCTAssertTrue([handler processKeyEvent:event]);
	XCTAssertEqual(target.invocationCount, 1);
}

- (void)testKeyEventHandlerReturnsNoForUnregisteredEvent
{
	GLTKeyEventTarget *target = [GLTKeyEventTarget new];
	TLOKeyEventHandler *handler = [[TLOKeyEventHandler alloc] initWithTarget:target];
	NSEvent *event = [self keyEventWithCharacters:@"z" modifiers:0 keyCode:6];

	XCTAssertFalse([handler processKeyEvent:event]);
	XCTAssertEqual(target.invocationCount, 0);
}

- (void)testNicknameCompletionCompletesLocalCommandAndPreservesCommandPrefix
{
	[IRCCommandIndex populateCommandIndex];

	GLTCompletionWindow *window = [[GLTCompletionWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 100)
																		 styleMask:NSWindowStyleMaskBorderless
																		   backing:NSBackingStoreBuffered
																			 defer:NO];
	window.testInputTextField = [[TVCMainWindowTextView alloc] initWithFrame:NSMakeRect(0, 0, 400, 100)];
	[window.contentView addSubview:window.testInputTextField];
	window.testInputTextField.stringValue = @"/jo";
	[window.testInputTextField setSelectedRange:NSMakeRange(3, 0)];

	TLONicknameCompletionStatus *completion = [[TLONicknameCompletionStatus alloc] initWithWindow:window];
	[completion completeNickname:YES];

	XCTAssertEqualObjects(window.testInputTextField.string, @"/join ");
	XCTAssertEqual(window.testInputTextField.selectedRange.location, 6);
}

- (void)testNicknameCompletionUsesChannelMembersAndConfiguredSuffix
{
	TPCPreferencesUserDefaults *defaults = TPCPreferencesUserDefaults.sharedUserDefaults;
	NSString *preferenceKey = @"Keyboard -> Tab Key Completion Suffix";
	id originalSuffix = [defaults objectForKey:preferenceKey];
	[defaults setObject:@": " forKey:preferenceKey];

	GLTTestClient *client = [GLTTestClient testClient];
	IRCUser *user = [[IRCUser alloc] initWithNickname:@"Alice" onClient:client];
	IRCChannelUser *member = [[IRCChannelUser alloc] initWithUser:user];
	GLTCompletionChannel *channel =
		[[GLTCompletionChannel alloc] initWithConfigDictionary:@{@"channelName" : @"#chat"}];
	channel.testMembers = @[ member ];

	GLTCompletionWindow *window = [[GLTCompletionWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 100)
																		 styleMask:NSWindowStyleMaskBorderless
																		   backing:NSBackingStoreBuffered
																			 defer:NO];
	window.testSelectedClient = client;
	window.testSelectedChannel = channel;
	window.testInputTextField = [[TVCMainWindowTextView alloc] initWithFrame:NSMakeRect(0, 0, 400, 100)];
	[window.contentView addSubview:window.testInputTextField];
	window.testInputTextField.stringValue = @"Al";
	[window.testInputTextField setSelectedRange:NSMakeRange(2, 0)];

	TLONicknameCompletionStatus *completion = [[TLONicknameCompletionStatus alloc] initWithWindow:window];
	[completion completeNickname:YES];

	XCTAssertEqualObjects(window.testInputTextField.string, @"Alice: ");

	if (originalSuffix) {
		[defaults setObject:originalSuffix forKey:preferenceKey];
	} else {
		[defaults removeObjectForKey:preferenceKey];
	}
}

- (NSEvent *)keyEventWithCharacters:(NSString *)characters
						  modifiers:(NSEventModifierFlags)modifiers
							keyCode:(unsigned short)keyCode
{
	return [NSEvent keyEventWithType:NSEventTypeKeyDown
							location:NSZeroPoint
					   modifierFlags:modifiers
						   timestamp:0
						windowNumber:0
							 context:nil
						  characters:characters
		 charactersIgnoringModifiers:characters
						   isARepeat:NO
							 keyCode:keyCode];
}

@end

NS_ASSUME_NONNULL_END
