/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

#import <XCTest/XCTest.h>

#import "GLTTestClient.h"
#import "IRCColorFormatPrivate.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRCColorFormatMigrationTests : XCTestCase
@end

@implementation IRCColorFormatMigrationTests

- (unichar)controlCharacterAtIndex:(NSUInteger)index inString:(NSString *)string
{
	return [string characterAtIndex:index];
}

- (void)testBooleanEffectsUseMatchingOpenAndCloseCharacters
{
	IRCTextFormatterEffect *bold = [IRCTextFormatterEffect effectWithType:IRCTextFormatterEffectBold];
	IRCTextFormatterEffect *italic = [IRCTextFormatterEffect effectWithType:IRCTextFormatterEffectItalic];
	IRCTextFormatterEffect *monospace = [IRCTextFormatterEffect effectWithType:IRCTextFormatterEffectMonospace];
	IRCTextFormatterEffect *strike = [IRCTextFormatterEffect effectWithType:IRCTextFormatterEffectStrikethrough];
	IRCTextFormatterEffect *underline = [IRCTextFormatterEffect effectWithType:IRCTextFormatterEffectUnderline];

	XCTAssertEqual(bold.controlCharacter, IRCTextFormatterEffectBoldCharacter);
	XCTAssertEqual(italic.controlCharacter, IRCTextFormatterEffectItalicCharacter);
	XCTAssertEqual(monospace.controlCharacter, IRCTextFormatterEffectMonospaceCharacter);
	XCTAssertEqual(strike.controlCharacter, IRCTextFormatterEffectStrikethroughCharacter);
	XCTAssertEqual(underline.controlCharacter, IRCTextFormatterEffectUnderlineCharacter);
	XCTAssertEqual(bold.length, 2);
	XCTAssertNil(bold.value);

	NSMutableString *buffer = [NSMutableString string];
	[bold appendToStartOf:buffer];
	[buffer appendString:@"x"];
	[bold appendToEndOf:buffer];

	XCTAssertEqual(buffer.length, 3);
	XCTAssertEqual([self controlCharacterAtIndex:0 inString:buffer], IRCTextFormatterEffectBoldCharacter);
	XCTAssertEqual([self controlCharacterAtIndex:2 inString:buffer], IRCTextFormatterEffectBoldCharacter);
}

- (void)testSpoilerIsAnAliasAndDoesNotCreateAnEffect
{
	XCTAssertNil([IRCTextFormatterEffect effectWithType:IRCTextFormatterEffectSpoiler]);
	XCTAssertNil([IRCTextFormatterEffect effectWithType:IRCTextFormatterEffectSpoiler withValue:@(YES)]);
}

- (void)testDigitAndHexColorsEncodeValuesAndBackgroundNeedsMatchingForeground
{
	IRCTextFormatterEffect *digitForeground =
		[IRCTextFormatterEffect effectWithType:IRCTextFormatterEffectForegroundColor withValue:@(4)];
	IRCTextFormatterEffect *hexForeground = [IRCTextFormatterEffect effectWithType:IRCTextFormatterEffectForegroundColor
																		 withValue:NSColor.redColor];
	IRCTextFormatterEffect *backgroundOnly =
		[IRCTextFormatterEffect effectWithType:IRCTextFormatterEffectBackgroundColor withValue:@(4)];

	XCTAssertEqual(digitForeground.controlCharacter, IRCTextFormatterEffectColorAsDigitCharacter);
	XCTAssertEqualObjects(digitForeground.value, @"04");
	XCTAssertEqual(digitForeground.length, 4);
	XCTAssertEqual(hexForeground.controlCharacter, IRCTextFormatterEffectColorAsHexCharacter);
	XCTAssertEqual(hexForeground.value.length, 6);
	XCTAssertNotNil(backgroundOnly);

	NSDictionary *digitPair =
		@{IRCTextFormatterForegroundColorAttributeName : @(4), IRCTextFormatterBackgroundColorAttributeName : @(14)};
	IRCTextFormatterEffects *matching = [IRCTextFormatterEffects effectsInAttributes:digitPair];
	XCTAssertEqual(matching.effects.count, 2);
	XCTAssertEqual(matching.maximumLength, 7);

	NSDictionary *mismatched = @{
		IRCTextFormatterForegroundColorAttributeName : @(4),
		IRCTextFormatterBackgroundColorAttributeName : NSColor.blueColor
	};
	IRCTextFormatterEffects *onlyForeground = [IRCTextFormatterEffects effectsInAttributes:mismatched];
	XCTAssertEqual(onlyForeground.effects.count, 1);

	NSDictionary *backgroundAlone = @{IRCTextFormatterBackgroundColorAttributeName : @(4)};
	XCTAssertEqual([IRCTextFormatterEffects effectsInAttributes:backgroundAlone].effects.count, 0);
}

- (void)testStringFormattedForIRCWrapsSegmentsWithControlCharacters
{
	NSMutableAttributedString *string =
		[[NSMutableAttributedString alloc] initWithString:@"hello"
											   attributes:@{NSFontAttributeName : [NSFont systemFontOfSize:13]}];
	[string setIRCFormatterAttribute:IRCTextFormatterEffectBold value:@(YES) range:string.range];
	[string setIRCFormatterAttribute:IRCTextFormatterEffectItalic value:@(YES) range:string.range];

	NSString *formatted = string.stringFormattedForIRC;

	XCTAssertTrue([string IRCFormatterAttributeSetInRange:IRCTextFormatterEffectBold range:string.range]);
	XCTAssertTrue([string IRCFormatterAttributeSetInRange:IRCTextFormatterEffectItalic range:string.range]);
	XCTAssertEqual([self controlCharacterAtIndex:0 inString:formatted], IRCTextFormatterEffectBoldCharacter);
	XCTAssertEqual([self controlCharacterAtIndex:1 inString:formatted], IRCTextFormatterEffectItalicCharacter);
	XCTAssertEqualObjects([formatted substringWithRange:NSMakeRange(2, 5)], @"hello");
	XCTAssertEqual([self controlCharacterAtIndex:7 inString:formatted], IRCTextFormatterEffectItalicCharacter);
	XCTAssertEqual([self controlCharacterAtIndex:8 inString:formatted], IRCTextFormatterEffectBoldCharacter);
}

- (void)testColorAttributeSetRequiresValidCodesAndNSColorIsAccepted
{
	NSMutableAttributedString *string =
		[[NSMutableAttributedString alloc] initWithString:@"hi"
											   attributes:@{NSFontAttributeName : [NSFont systemFontOfSize:13]}];

	[string setIRCFormatterAttribute:IRCTextFormatterEffectForegroundColor value:@(99) range:string.range];
	XCTAssertFalse([string IRCFormatterAttributeSetInRange:IRCTextFormatterEffectForegroundColor range:string.range]);

	[string setIRCFormatterAttribute:IRCTextFormatterEffectForegroundColor value:@(12) range:string.range];
	XCTAssertTrue([string IRCFormatterAttributeSetInRange:IRCTextFormatterEffectForegroundColor range:string.range]);

	[string setIRCFormatterAttribute:IRCTextFormatterEffectBackgroundColor value:NSColor.blackColor range:string.range];
	XCTAssertTrue([string IRCFormatterAttributeSetInRange:IRCTextFormatterEffectBackgroundColor range:string.range]);
}

- (void)testRemovingBoldClearsFormatterAndTrait
{
	NSMutableAttributedString *string =
		[[NSMutableAttributedString alloc] initWithString:@"bold"
											   attributes:@{NSFontAttributeName : [NSFont systemFontOfSize:13]}];
	[string setIRCFormatterAttribute:IRCTextFormatterEffectBold value:@(YES) range:string.range];
	XCTAssertTrue([string IRCFormatterAttributeSetInRange:IRCTextFormatterEffectBold range:string.range]);

	[string removeIRCFormatterAttribute:IRCTextFormatterEffectBold range:string.range];
	XCTAssertFalse([string IRCFormatterAttributeSetInRange:IRCTextFormatterEffectBold range:string.range]);
}

- (void)testWrapHelperDeletesBackToWhitespaceInsideMaxDistance
{
	NSMutableString *string = [NSMutableString stringWithString:@"aaaa bbbb cccc dddd eeee ffff gggg hhhh iiii"];
	NSUInteger deleted = [string wrapIRCTextFormatterResultWith:0 maxDistance:25];

	XCTAssertNotEqual(deleted, NSNotFound);
	XCTAssertTrue([string hasPrefix:@"aaaa bbbb cccc dddd eeee ffff gggg hhhh"]);
	XCTAssertFalse([string containsString:@"iiii"]);
	XCTAssertFalse([string hasSuffix:@" "]);
}

- (void)testChannelFormattingTruncatesLongMessagesAndReportsEffectiveRange
{
	GLTTestClient *client = [GLTTestClient testClient];
	NSString *payload = [@"" stringByPaddingToLength:800 withString:@"abcdefghij " startingAtIndex:0];
	NSAttributedString *string = [[NSAttributedString alloc] initWithString:payload];
	NSRange effectiveRange = NSMakeRange(NSNotFound, 0);

	NSString *formatted = [string stringFormattedForChannel:@"#test"
												   onClient:client
											   withLineType:TVCLogLineTypePrivateMessage
											 effectiveRange:&effectiveRange];

	XCTAssertGreaterThan(formatted.length, 0);
	XCTAssertLessThan(formatted.length, payload.length);
	XCTAssertEqual(effectiveRange.location, 0);
	XCTAssertGreaterThan(effectiveRange.length, 0);
	XCTAssertLessThan(effectiveRange.length, payload.length);
}

- (void)testMutableChannelFormattingDeletesConsumedPrefix
{
	GLTTestClient *client = [GLTTestClient testClient];
	NSString *payload = [@"" stringByPaddingToLength:800 withString:@"word " startingAtIndex:0];
	NSMutableAttributedString *string = [[NSMutableAttributedString alloc] initWithString:payload];
	NSUInteger originalLength = string.length;

	NSString *formatted = [string stringFormattedForChannel:@"#test" onClient:client withLineType:TVCLogLineTypeNotice];

	XCTAssertGreaterThan(formatted.length, 0);
	XCTAssertLessThan(string.length, originalLength);
	XCTAssertEqual(string.length + formatted.length, originalLength);
}

@end

NS_ASSUME_NONNULL_END
