/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

#import <XCTest/XCTest.h>

#import "IRCUserNicknameColorStyleGeneratorPrivate.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRCUserNicknameColorStyleGeneratorTests : XCTestCase
@end

@implementation IRCUserNicknameColorStyleGeneratorTests

- (void)testHashRemainsCompatibleWithLegacyMD5ByteOrder
{
	NSNumber *hash = [IRCUserNicknameColorStyleGenerator hashForString:@"alice"
															colorStyle:TPCThemeSettingsNicknameColorStyleLight];

	XCTAssertEqual(hash.unsignedIntValue, 2746080018U);
}

- (void)testLightAndDarkStylesRemainStable
{
	NSNumber *hash = @(2746080018U);

	XCTAssertEqualObjects([IRCUserNicknameColorStyleGenerator
							  nicknameColorStyleForHash:hash
											 colorStyle:TPCThemeSettingsNicknameColorStyleLight],
						  @"hsl(18,45%,54%)");
	XCTAssertEqualObjects([IRCUserNicknameColorStyleGenerator
							  nicknameColorStyleForHash:hash
											 colorStyle:TPCThemeSettingsNicknameColorStyleDark],
						  @"hsl(18,45%,49%)");
}

- (void)testHueSpecificAdjustmentsRemainStable
{
	XCTAssertEqualObjects([IRCUserNicknameColorStyleGenerator
							  nicknameColorStyleForHash:@(1507889104U)
											 colorStyle:TPCThemeSettingsNicknameColorStyleDark],
						  @"hsl(304,47%,54%)");
	XCTAssertEqualObjects([IRCUserNicknameColorStyleGenerator
							  nicknameColorStyleForHash:@(3807608927U)
											 colorStyle:TPCThemeSettingsNicknameColorStyleLight],
						  @"hsl(167,78%,34%)");
}

@end

NS_ASSUME_NONNULL_END
