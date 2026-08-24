/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

#import <XCTest/XCTest.h>

#import "OELReachabilityPrivate.h"

NS_ASSUME_NONNULL_BEGIN

@interface OELReachabilityMigrationTests : XCTestCase
@end

@implementation OELReachabilityMigrationTests

- (void)testFactoryCreatesNotifier
{
	OELReachability *reachability = [OELReachability reachabilityForInternetConnection];

	XCTAssertNotNil(reachability);
	XCTAssertFalse(reachability.isReachable);
}

- (void)testFirstPathSeedsWithoutEvent
{
	BOOL currentlyReachable = NO;
	BOOL receivedInitialPath = NO;

	NSInteger event = [OELReachability evaluatePathChange:YES
									   currentlyReachable:&currentlyReachable
									  receivedInitialPath:&receivedInitialPath];

	XCTAssertEqual(event, 0);
	XCTAssertTrue(currentlyReachable);
	XCTAssertTrue(receivedInitialPath);
}

- (void)testUnchangedPathProducesNoEvent
{
	BOOL currentlyReachable = YES;
	BOOL receivedInitialPath = YES;

	NSInteger event = [OELReachability evaluatePathChange:YES
									   currentlyReachable:&currentlyReachable
									  receivedInitialPath:&receivedInitialPath];

	XCTAssertEqual(event, 0);
	XCTAssertTrue(currentlyReachable);
}

- (void)testReachabilityTransitionsEmitExpectedEvents
{
	BOOL currentlyReachable = YES;
	BOOL receivedInitialPath = YES;

	NSInteger becameUnreachable = [OELReachability evaluatePathChange:NO
												   currentlyReachable:&currentlyReachable
												  receivedInitialPath:&receivedInitialPath];
	XCTAssertEqual(becameUnreachable, 2);
	XCTAssertFalse(currentlyReachable);

	NSInteger becameReachable = [OELReachability evaluatePathChange:YES
												 currentlyReachable:&currentlyReachable
												receivedInitialPath:&receivedInitialPath];
	XCTAssertEqual(becameReachable, 1);
	XCTAssertTrue(currentlyReachable);
}

- (void)testStartAndStopNotifierRoundTrip
{
	OELReachability *reachability = [OELReachability reachabilityForInternetConnection];

	XCTAssertTrue([reachability startNotifier]);
	[reachability stopNotifier];
	XCTAssertTrue([reachability startNotifier]);
	[reachability stopNotifier];
}

@end

NS_ASSUME_NONNULL_END
