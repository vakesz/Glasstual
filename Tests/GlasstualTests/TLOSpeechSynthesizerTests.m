/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

#import <XCTest/XCTest.h>

#import "GLTTestClient.h"
#import "TLOSpokenNotificationPrivate.h"
#import "TLOSpeechSynthesizerTestingPrivate.h"

NS_ASSUME_NONNULL_BEGIN

@interface TLOSpeechSynthesizerEngineSpy : NSObject <TLOSpeechSynthesizerEngine>
@property(nonatomic, weak, nullable) id<TLOSpeechSynthesizerEngineDelegate> delegate;
@property(nonatomic, getter=isSpeaking) BOOL speaking;
@property(nonatomic) NSUInteger stopCount;
@property(nonatomic, strong) NSMutableArray<NSString *> *spokenTexts;

- (void)completeCurrentUtterance;
@end

@implementation TLOSpeechSynthesizerEngineSpy

- (instancetype)init
{
	if ((self = [super init])) {
		self.spokenTexts = [NSMutableArray array];
	}

	return self;
}

- (void)speakText:(NSString *)text
{
	[self.spokenTexts addObject:text];
	self.speaking = YES;
}

- (void)stopSpeakingImmediately
{
	self.stopCount += 1;
	self.speaking = NO;
}

- (void)completeCurrentUtterance
{
	self.speaking = NO;
	[self.delegate speechSynthesizerEngineDidCompleteUtterance];
}

@end

@interface TLOSpeechSynthesizerTests : XCTestCase
@end

@implementation TLOSpeechSynthesizerTests

- (void)testQueuedTextStartsInOrderAsUtterancesComplete
{
	TLOSpeechSynthesizerEngineSpy *engine = [TLOSpeechSynthesizerEngineSpy new];
	TLOSpeechSynthesizer *synthesizer = [[TLOSpeechSynthesizer alloc] initWithEngine:engine];

	[synthesizer speak:@"first"];
	[synthesizer speak:@"second"];

	XCTAssertEqualObjects(engine.spokenTexts, (@[ @"first" ]));
	XCTAssertEqual(synthesizer.pendingItemCount, 1);

	[engine completeCurrentUtterance];

	XCTAssertEqualObjects(engine.spokenTexts, (@[ @"first", @"second" ]));
	XCTAssertEqual(synthesizer.pendingItemCount, 0);
}

- (void)testStoppingRejectsNewItemsAndStopsCurrentUtterance
{
	TLOSpeechSynthesizerEngineSpy *engine = [TLOSpeechSynthesizerEngineSpy new];
	TLOSpeechSynthesizer *synthesizer = [[TLOSpeechSynthesizer alloc] initWithEngine:engine];

	[synthesizer speak:@"active"];
	synthesizer.isStopped = YES;
	[synthesizer speak:@"ignored"];

	XCTAssertEqual(engine.stopCount, 1);
	XCTAssertEqualObjects(engine.spokenTexts, (@[ @"active" ]));
	XCTAssertEqual(synthesizer.pendingItemCount, 0);
}

- (void)testClearQueueLeavesCurrentUtteranceAlone
{
	TLOSpeechSynthesizerEngineSpy *engine = [TLOSpeechSynthesizerEngineSpy new];
	TLOSpeechSynthesizer *synthesizer = [[TLOSpeechSynthesizer alloc] initWithEngine:engine];

	[synthesizer speak:@"active"];
	[synthesizer speak:@"queued"];
	[synthesizer clearQueue];

	XCTAssertTrue(engine.isSpeaking);
	XCTAssertEqual(synthesizer.pendingItemCount, 0);
	XCTAssertEqualObjects(engine.spokenTexts, (@[ @"active" ]));
}

- (void)testClearQueueForClientRemovesOnlyMatchingNotifications
{
	TLOSpeechSynthesizerEngineSpy *engine = [TLOSpeechSynthesizerEngineSpy new];
	engine.speaking = YES;

	TLOSpeechSynthesizer *synthesizer = [[TLOSpeechSynthesizer alloc] initWithEngine:engine];
	GLTTestClient *firstClient = [GLTTestClient testClient];
	GLTTestClient *secondClient = [GLTTestClient testClient];
	TLOSpokenNotification *firstNotification =
		[[TLOSpokenNotification alloc] initWithNotification:TXNotificationTypeConnect
												   lineType:TVCLogLineTypeNotice
													 target:firstClient
												   nickname:@"first"
													   text:@"one"];
	TLOSpokenNotification *secondNotification =
		[[TLOSpokenNotification alloc] initWithNotification:TXNotificationTypeConnect
												   lineType:TVCLogLineTypeNotice
													 target:secondClient
												   nickname:@"second"
													   text:@"two"];

	[synthesizer speak:firstNotification];
	[synthesizer speak:secondNotification];
	[synthesizer speak:@"plain text"];

	[synthesizer clearQueueForClient:firstClient];

	XCTAssertEqual(synthesizer.pendingItemCount, 2);

	[engine completeCurrentUtterance];

	XCTAssertEqual(synthesizer.pendingItemCount, 1);
}

- (void)testUnsupportedQueueItemDoesNotBlockFollowingText
{
	TLOSpeechSynthesizerEngineSpy *engine = [TLOSpeechSynthesizerEngineSpy new];
	engine.speaking = YES;

	TLOSpeechSynthesizer *synthesizer = [[TLOSpeechSynthesizer alloc] initWithEngine:engine];

	[synthesizer speak:@42];
	[synthesizer speak:@"valid"];

	[engine completeCurrentUtterance];

	XCTAssertEqualObjects(engine.spokenTexts, (@[ @"valid" ]));
	XCTAssertEqual(synthesizer.pendingItemCount, 0);
}

@end

NS_ASSUME_NONNULL_END
