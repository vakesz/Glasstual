/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

#import <XCTest/XCTest.h>

#import "GLTTestClient.h"
#import "IRCChannelPrivate.h"
#import "IRCTreeItemPrivate.h"
#import "NSColorHelper.h"
#import "NSTableVIewHelperPrivate.h"
#import "TDCChannelModifyTopicSheetPrivate.h"
#import "TDCOnboardingSteps.h"
#import "TDCPreferencesControllerPrivate.h"
#import "TDCWindowBase.h"
#import "THOUnicodeHelper.h"
#import "TLOSpokenNotificationPrivate.h"
#import "TVCAutoExpandingTextField.h"
#import "TVCAutoExpandingTokenField.h"
#import "TVCMemberListUserInfoPopoverPrivate.h"
#import "TXAppearanceHelper.h"

NS_ASSUME_NONNULL_BEGIN

@interface GLTWindowSpy : NSWindow
@property(nonatomic) NSUInteger orderFrontCount;
@property(nonatomic) NSUInteger closeCount;
@end

@implementation GLTWindowSpy

- (void)makeKeyAndOrderFront:(nullable id)sender
{
	self.orderFrontCount += 1;
}

- (void)close
{
	self.closeCount += 1;
}

@end

@interface GLTAppearanceSpyView : NSView
@property(nonatomic) NSUInteger applicationAppearanceChangeCount;
@property(nonatomic) NSUInteger systemAppearanceChangeCount;
@end

@implementation GLTAppearanceSpyView

- (BOOL)needsDisplayWhenApplicationAppearanceChanges
{
	return YES;
}

- (BOOL)needsDisplayWhenSystemAppearanceChanges
{
	return YES;
}

- (void)applicationAppearanceChanged
{
	self.applicationAppearanceChangeCount += 1;
	[super applicationAppearanceChanged];
}

- (void)systemAppearanceChanged
{
	self.systemAppearanceChangeCount += 1;
	[super systemAppearanceChanged];
}

@end

@interface AppKitSupportMigrationTests : XCTestCase
@end

@implementation AppKitSupportMigrationTests

- (void)testAutoExpandingFieldsTrackTheirLayoutWidth
{
	TVCAutoExpandingTextField *textField = [[TVCAutoExpandingTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 20)];
	textField.cell.wraps = YES;

	[textField layout];

	XCTAssertEqual(textField.preferredMaxLayoutWidth, 240);

	TVCAutoExpandingTokenField *tokenField =
		[[TVCAutoExpandingTokenField alloc] initWithFrame:NSMakeRect(0, 0, 180, 20)];
	tokenField.cell.wraps = YES;

	[tokenField layout];

	XCTAssertEqual(tokenField.preferredMaxLayoutWidth, 180);
}

- (void)testAutoExpandingHelperIgnoresNonWrappingFields
{
	NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 20)];
	field.cell.wraps = NO;

	XCTAssertFalse(TVCAutoExpandingFieldUpdatePreferredMaxLayoutWidth(field));
	XCTAssertEqual(field.preferredMaxLayoutWidth, 0);
}

- (void)testWindowBaseForwardsWindowLifecycleActions
{
	GLTWindowSpy *window = [GLTWindowSpy new];
	TDCWindowBase *controller = [TDCWindowBase new];
	controller.window = window;

	[controller show];
	[controller ok:nil];
	[controller cancel:nil];

	XCTAssertEqual(window.orderFrontCount, 1);
	XCTAssertEqual(window.closeCount, 2);
}

- (void)testPreferencesControllerLoadsWindowFromNib
{
	TDCPreferencesController *controller = [TDCPreferencesController new];

	XCTAssertNotNil(controller.window);

	/* Avoid ordering the full preferences UI front in the TEST_HOST
	 process — pane setup pulls in web views / plugins and can abort
	 the suite. Nib outlet wiring is what this test guards. */
}

- (void)testMemberInfoPopoverUsesTransientBehavior
{
	TVCMemberListUserInfoPopover *popover = [TVCMemberListUserInfoPopover new];

	[popover awakeFromNib];

	XCTAssertEqual(popover.behavior, NSPopoverBehaviorTransient);
}

- (void)testChannelModifyTopicSheetLoadsFromNib
{
	GLTTestClient *client = [GLTTestClient testClient];
	IRCChannel *channel = [[IRCChannel alloc] initWithConfigDictionary:@{@"channelName" : @"#chat"}];

	channel.associatedClient = client;

	TDCChannelModifyTopicSheet *sheet = [[TDCChannelModifyTopicSheet alloc] initWithChannel:channel];

	XCTAssertEqual(sheet.client, client);
	XCTAssertEqual(sheet.channel, channel);
	XCTAssertEqualObjects(sheet.channelId, channel.uniqueIdentifier);
	XCTAssertNotNil(sheet.sheet);
}

- (void)testOnboardingStylePreviewViewExposesRadioButtonAccessibility
{
	TDCOnboardingStylePreviewView *view = [TDCOnboardingStylePreviewView new];

	view.styleTitle = @"Bubbles";

	XCTAssertTrue(view.isAccessibilityElement);
	XCTAssertEqualObjects(view.accessibilityRole, NSAccessibilityRadioButtonRole);
	XCTAssertEqualObjects(view.accessibilityLabel, @"Bubbles");
	XCTAssertEqualObjects(view.accessibilityValue, @NO);

	view.selected = YES;

	XCTAssertEqualObjects(view.accessibilityValue, @YES);
}

- (void)testSpokenNotificationResolvesClientTarget
{
	GLTTestClient *client = [GLTTestClient testClient];
	TLOSpokenNotification *notification = [[TLOSpokenNotification alloc] initWithNotification:TXNotificationTypeConnect
																					 lineType:TVCLogLineTypeNotice
																					   target:client
																					 nickname:@"alice"
																						 text:@"connected"];

	XCTAssertEqual(notification.client, client);
	XCTAssertNil(notification.channel);
	XCTAssertEqual(notification.notificationType, TXNotificationTypeConnect);
	XCTAssertEqual(notification.lineType, TVCLogLineTypeNotice);
	XCTAssertEqualObjects(notification.nickname, @"alice");
	XCTAssertEqualObjects(notification.text, @"connected");
}

- (void)testSpokenNotificationResolvesChannelAndItsClient
{
	GLTTestClient *client = [GLTTestClient testClient];
	IRCChannel *channel = [[IRCChannel alloc] initWithConfigDictionary:@{@"channelName" : @"#chat"}];
	channel.associatedClient = client;

	TLOSpokenNotification *notification =
		[[TLOSpokenNotification alloc] initWithNotification:TXNotificationTypeChannelMessage
												   lineType:TVCLogLineTypePrivateMessage
													 target:channel
												   nickname:@"alice"
													   text:@"hello"];

	XCTAssertEqual(notification.client, client);
	XCTAssertEqual(notification.channel, channel);
}

- (void)testPreferredGlobalTableViewFontMatchesLegacySize
{
	NSFont *font = [NSTableView preferredGlobalTableViewFont];

	XCTAssertEqualWithAccuracy(font.pointSize, 13.0, 0.001);
}

- (void)testFormatterColorsIncludeCanonicalIRCPalette
{
	XCTAssertEqual(NSColor.formatterColors.count, 99);
	XCTAssertEqualObjects(NSColor.formatterWhiteColor, NSColor.formatterColors[0]);
	XCTAssertEqualObjects(NSColor.formatterBlackColor, NSColor.formatterColors[1]);
	XCTAssertEqualObjects(NSColor.formatterLightGrayColor, NSColor.formatterColors[15]);
}

- (void)testAppearanceNotificationsPropagateToSubviews
{
	NSView *parent = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
	GLTAppearanceSpyView *child = [[GLTAppearanceSpyView alloc] initWithFrame:NSMakeRect(0, 0, 50, 50)];
	[parent addSubview:child];

	[parent notifyApplicationAppearanceChanged];
	[parent notifySystemAppearanceChanged];

	XCTAssertEqual(child.applicationAppearanceChangeCount, 1);
	XCTAssertEqual(child.systemAppearanceChangeCount, 1);
}

- (void)testUnicodeHelperClassifiesCodePoints
{
	XCTAssertTrue([THOUnicodeHelper isAlphabeticalCodePoint:'A']);
	XCTAssertTrue([THOUnicodeHelper isAlphabeticalCodePoint:'z']);
	XCTAssertFalse([THOUnicodeHelper isAlphabeticalCodePoint:'1']);
	XCTAssertTrue([THOUnicodeHelper isPrivate:0xe010]);
	XCTAssertTrue([THOUnicodeHelper isIdeographic:0x4e00]);
	XCTAssertTrue([THOUnicodeHelper isIdeographicOrPrivate:0xe010]);
}

@end

NS_ASSUME_NONNULL_END
