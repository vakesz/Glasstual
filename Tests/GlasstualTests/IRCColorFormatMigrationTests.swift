import XCTest

// Preprocessor directives found in file:
// #import <XCTest/XCTest.h>
// #import "GLTTestClient.h"
// #import "IRCColorFormatPrivate.h"
/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */
@objc
class IRCColorFormatMigrationTests: XCTestCase {
    @objc
    func controlCharacterAtIndex(_ index: UInt, inString string: String) -> unichar {
        return string.characterAtIndex(index)
    }
    @objc
    func testBooleanEffectsUseMatchingOpenAndCloseCharacters() {
        let bold: UnsafeMutablePointer<IRCTextFormatterEffect>! = IRCTextFormatterEffect.effectWithType(IRCTextFormatterEffectBold)
        let italic: UnsafeMutablePointer<IRCTextFormatterEffect>! = IRCTextFormatterEffect.effectWithType(IRCTextFormatterEffectItalic)
        let monospace: UnsafeMutablePointer<IRCTextFormatterEffect>! = IRCTextFormatterEffect.effectWithType(IRCTextFormatterEffectMonospace)
        let strike: UnsafeMutablePointer<IRCTextFormatterEffect>! = IRCTextFormatterEffect.effectWithType(IRCTextFormatterEffectStrikethrough)
        let underline: UnsafeMutablePointer<IRCTextFormatterEffect>! = IRCTextFormatterEffect.effectWithType(IRCTextFormatterEffectUnderline)

        XCTAssertEqual(bold.controlCharacter, IRCTextFormatterEffectBoldCharacter)
        XCTAssertEqual(italic.controlCharacter, IRCTextFormatterEffectItalicCharacter)
        XCTAssertEqual(monospace.controlCharacter, IRCTextFormatterEffectMonospaceCharacter)
        XCTAssertEqual(strike.controlCharacter, IRCTextFormatterEffectStrikethroughCharacter)
        XCTAssertEqual(underline.controlCharacter, IRCTextFormatterEffectUnderlineCharacter)
        XCTAssertEqual(bold.length, 2)

        XCTAssertNil(bold.value)

        let buffer = NSMutableString()

        bold.appendToStartOf(buffer)

        buffer.append("x")

        bold.appendToEndOf(buffer)

        XCTAssertEqual(buffer.length, 3)
        XCTAssertEqual(self.controlCharacterAtIndex(0, inString: buffer), IRCTextFormatterEffectBoldCharacter)
        XCTAssertEqual(self.controlCharacterAtIndex(2, inString: buffer), IRCTextFormatterEffectBoldCharacter)
    }
    @objc
    func testSpoilerIsAnAliasAndDoesNotCreateAnEffect() {
        XCTAssertNil(IRCTextFormatterEffect.effectWithType(IRCTextFormatterEffectSpoiler))
        XCTAssertNil(IRCTextFormatterEffect.effectWithType(IRCTextFormatterEffectSpoiler, withValue: true))
    }
    @objc
    func testDigitAndHexColorsEncodeValuesAndBackgroundNeedsMatchingForeground() {
        let digitForeground: UnsafeMutablePointer<IRCTextFormatterEffect>! = IRCTextFormatterEffect.effectWithType(IRCTextFormatterEffectForegroundColor, withValue: 4)
        let hexForeground: UnsafeMutablePointer<IRCTextFormatterEffect>! = IRCTextFormatterEffect.effectWithType(IRCTextFormatterEffectForegroundColor, withValue: NSColor.redColor)
        let backgroundOnly: UnsafeMutablePointer<IRCTextFormatterEffect>! = IRCTextFormatterEffect.effectWithType(IRCTextFormatterEffectBackgroundColor, withValue: 4)

        XCTAssertEqual(digitForeground.controlCharacter, IRCTextFormatterEffectColorAsDigitCharacter)

        XCTAssertEqualObjects(digitForeground.value, "04")

        XCTAssertEqual(digitForeground.length, 4)
        XCTAssertEqual(hexForeground.controlCharacter, IRCTextFormatterEffectColorAsHexCharacter)
        XCTAssertEqual(hexForeground.value.length, 6)

        XCTAssertNotNil(backgroundOnly)

        let digitPair: NSDictionary! = [IRCTextFormatterForegroundColorAttributeName: 4, IRCTextFormatterBackgroundColorAttributeName: 14]
        let matching: UnsafeMutablePointer<IRCTextFormatterEffects>! = IRCTextFormatterEffects.effectsInAttributes(digitPair)

        XCTAssertEqual(matching.effects.count, 2)
        XCTAssertEqual(matching.maximumLength, 7)

        let mismatched: NSDictionary! = [IRCTextFormatterForegroundColorAttributeName: 4, IRCTextFormatterBackgroundColorAttributeName: NSColor.blueColor]
        let onlyForeground: UnsafeMutablePointer<IRCTextFormatterEffects>! = IRCTextFormatterEffects.effectsInAttributes(mismatched)

        XCTAssertEqual(onlyForeground.effects.count, 1)

        let backgroundAlone: NSDictionary! = [IRCTextFormatterBackgroundColorAttributeName: 4]

        XCTAssertEqual(IRCTextFormatterEffects.effectsInAttributes(backgroundAlone).effects.count, 0)
    }
    @objc
    func testStringFormattedForIRCWrapsSegmentsWithControlCharacters() {
        let string: NSMutableAttributedString! = NSMutableAttributedString(string: "hello", attributes: [NSFontAttributeName: UIFont.systemFont(ofSize: 13)])

        string.setIRCFormatterAttribute(IRCTextFormatterEffectBold, value: true, range: string.range)
        string.setIRCFormatterAttribute(IRCTextFormatterEffectItalic, value: true, range: string.range)

        let formatted: String! = string.stringFormattedForIRC

        XCTAssertTrue(string.IRCFormatterAttributeSetInRange(IRCTextFormatterEffectBold, range: string.range))
        XCTAssertTrue(string.IRCFormatterAttributeSetInRange(IRCTextFormatterEffectItalic, range: string.range))

        XCTAssertEqual(self.controlCharacterAtIndex(0, inString: formatted), IRCTextFormatterEffectBoldCharacter)
        XCTAssertEqual(self.controlCharacterAtIndex(1, inString: formatted), IRCTextFormatterEffectItalicCharacter)

        XCTAssertEqualObjects(formatted.substringWithRange(NSMakeRange(2, 5)), "hello")

        XCTAssertEqual(self.controlCharacterAtIndex(7, inString: formatted), IRCTextFormatterEffectItalicCharacter)
        XCTAssertEqual(self.controlCharacterAtIndex(8, inString: formatted), IRCTextFormatterEffectBoldCharacter)
    }
    @objc
    func testColorAttributeSetRequiresValidCodesAndNSColorIsAccepted() {
        let string: NSMutableAttributedString! = NSMutableAttributedString(string: "hi", attributes: [NSFontAttributeName: UIFont.systemFont(ofSize: 13)])

        string.setIRCFormatterAttribute(IRCTextFormatterEffectForegroundColor, value: 99, range: string.range)

        XCTAssertFalse(string.IRCFormatterAttributeSetInRange(IRCTextFormatterEffectForegroundColor, range: string.range))

        string.setIRCFormatterAttribute(IRCTextFormatterEffectForegroundColor, value: 12, range: string.range)

        XCTAssertTrue(string.IRCFormatterAttributeSetInRange(IRCTextFormatterEffectForegroundColor, range: string.range))

        string.setIRCFormatterAttribute(IRCTextFormatterEffectBackgroundColor, value: NSColor.blackColor, range: string.range)

        XCTAssertTrue(string.IRCFormatterAttributeSetInRange(IRCTextFormatterEffectBackgroundColor, range: string.range))
    }
    @objc
    func testRemovingBoldClearsFormatterAndTrait() {
        let string: NSMutableAttributedString! = NSMutableAttributedString(string: "bold", attributes: [NSFontAttributeName: UIFont.systemFont(ofSize: 13)])

        string.setIRCFormatterAttribute(IRCTextFormatterEffectBold, value: true, range: string.range)

        XCTAssertTrue(string.IRCFormatterAttributeSetInRange(IRCTextFormatterEffectBold, range: string.range))

        string.removeIRCFormatterAttribute(IRCTextFormatterEffectBold, range: string.range)

        XCTAssertFalse(string.IRCFormatterAttributeSetInRange(IRCTextFormatterEffectBold, range: string.range))
    }
    @objc
    func testWrapHelperDeletesBackToWhitespaceInsideMaxDistance() {
        let string: NSMutableString! = NSMutableString.stringWithString("aaaa bbbb cccc dddd eeee ffff gggg hhhh iiii")
        let deleted: UInt = string.wrapIRCTextFormatterResultWith(0, maxDistance: 25)

        XCTAssertNotEqual(deleted, NSNotFound)

        XCTAssertTrue(string.hasPrefix("aaaa bbbb cccc dddd eeee ffff gggg hhhh"))

        XCTAssertFalse(string.containsString("iiii"))
        XCTAssertFalse(string.hasSuffix(" "))
    }
    @objc
    func testChannelFormattingTruncatesLongMessagesAndReportsEffectiveRange() {
        let client: UnsafeMutablePointer<GLTTestClient>! = GLTTestClient.testClient()
        let payload: String! = "".stringByPaddingToLength(800, withString: "abcdefghij ", startingAtIndex: 0)
        let string: NSAttributedString! = NSAttributedString(string: payload)
        var effectiveRange: NSRange = NSMakeRange(NSNotFound, 0)
        let formatted: String! = string.stringFormattedForChannel("#test", onClient: client, withLineType: TVCLogLineTypePrivateMessage, effectiveRange: &effectiveRange)

        XCTAssertGreaterThan(formatted.length, 0)

        XCTAssertLessThan(formatted.length, payload.length)

        XCTAssertEqual(effectiveRange.location, 0)

        XCTAssertGreaterThan(effectiveRange.length, 0)

        XCTAssertLessThan(effectiveRange.length, payload.length)
    }
    @objc
    func testMutableChannelFormattingDeletesConsumedPrefix() {
        let client: UnsafeMutablePointer<GLTTestClient>! = GLTTestClient.testClient()
        let payload: String! = "".stringByPaddingToLength(800, withString: "word ", startingAtIndex: 0)
        let string: NSMutableAttributedString! = NSMutableAttributedString(string: payload)
        let originalLength: UInt = string.length
        let formatted: String! = string.stringFormattedForChannel("#test", onClient: client, withLineType: TVCLogLineTypeNotice)

        XCTAssertGreaterThan(formatted.length, 0)
        XCTAssertLessThan(string.length, originalLength)
        XCTAssertEqual(string.length + formatted.length, originalLength)
    }
}