/* *********************************************************************
 *
 *         Copyright (c) 2015 - 2018 Codeux Software, LLC
 *     Please see ACKNOWLEDGEMENT for additional information.
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
 *  * Neither the name of "Codeux Software, LLC", nor the names of its
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
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

#include <Availability.h>

NS_ASSUME_NONNULL_BEGIN

#define CS_StringIsBase10Numeric(c)					('0' <= (c) && (c) <= '9')
#define CS_StringIsAlphabetic(c)					('a' <= (c) && (c) <= 'z' || 'A' <= (c) && (c) <= 'Z')
COCOA_EXTENSIONS_EXTERN NSString * const NSStringEmptyPlaceholder;
COCOA_EXTENSIONS_EXTERN NSString * const NSStringNewlinePlaceholder;
COCOA_EXTENSIONS_EXTERN NSString * const NSStringWhitespacePlaceholder;

COCOA_EXTENSIONS_EXTERN NSString * const CS_UnicodeReplacementCharacter;

typedef NS_OPTIONS(NSUInteger, CSStringType)
{
	CSStringTypeAny 			= 1 << 0, // Always returns YES when length > 0
	CSStringTypeWholeNumber		= 1 << 1, // No decimal place allowed
	CSStringTypeDecimalNumber 	= 1 << 2, // One decimal place allowed
	CSStringTypePositiveNumber 	= 1 << 3, // Positive number
	CSStringTypeNegativeNumber	= 1 << 4, // Negative number
	CSStringTypeAnyNumber 		= (CSStringTypeWholeNumber |
								   CSStringTypeDecimalNumber |
								   CSStringTypePositiveNumber |
								   CSStringTypeNegativeNumber),
	CSStringTypeAlphabetic		= 1 << 10 // a to z, A to Z
};

#pragma mark
#pragma mark String Helpers

@interface NSString (CSStringHelper)
+ (nullable instancetype)stringWithBytes:(const void *)bytes length:(NSUInteger)length encoding:(NSStringEncoding)encoding;
+ (nullable instancetype)stringWithData:(NSData *)data encoding:(NSStringEncoding)encoding;

@property (readonly, copy, nullable) NSString *sha1;
@property (readonly, copy, nullable) NSString *sha256;
@property (readonly, copy, nullable) NSString *sha512;

@property (readonly) NSRange range;

+ (NSString *)stringWithUUID;

+ (nullable NSString *)charsetRepFromStringEncoding:(NSStringEncoding)encoding;
+ (NSDictionary<NSString *, NSNumber *> *)supportedStringEncodingsWithTitle:(BOOL)favorUTF8;

- (NSString *)substringAfterIndex:(NSUInteger)anIndex;
/* -substringAtIndex:toLength: uses individual arguments as signed
 integers to allow negative values when creating substring. */
/* A negative atIndex value will create a substring starting at
 location 0 and ending at string length minus atIndex
 For example: given "An example" (length 10), atIndex = -2, toLength = 0
 Result is: "An examp" */
/* A negative toLength value will create a substring starting at
 string length minus atLength until string length.
 For example: given "An example" (length 10), atIndex = 0, toLength = -2
 Result is: "le" */
/* If atIndex and toLength are both negative, then atIndex is taken
 from location 0 and toLength is taken from string length.
 For example: given "An example" (length 10), atIndex = -2, toLength = -2
 Result is: " examp" */
- (NSString *)substringAtIndex:(NSInteger)atIndex toLength:(NSInteger)toLength;

- (NSString *)substringFromIndex:(NSUInteger)atIndex toIndex:(NSUInteger)toIndex;

- (NSString *)stringCharacterAtIndex:(NSUInteger)anIndex;

- (CGFloat)compareWithWord:(NSString *)stringB lengthPenaltyWeight:(CGFloat)weight;

- (BOOL)hasPrefixIgnoringCase:(NSString *)aString; // Performs literal comparison
- (BOOL)hasSuffixWithCharacterSet:(NSCharacterSet *)characterSet;

- (BOOL)isEqualToStringIgnoringCase:(NSString *)other;

- (BOOL)contains:(NSString *)string; // Performs literal comparison
- (BOOL)containsIgnoringCase:(NSString *)string; // Performs literal comparison

- (BOOL)containsCharactersFromCharacterSet:(NSCharacterSet *)characterSet;
- (BOOL)onlyContainsCharactersFromCharacterSet:(NSCharacterSet *)characterSet;

- (BOOL)containsCharacters:(NSString *)characters;
- (NSUInteger)occurrencesOfCharacter:(UniChar)character;

- (NSInteger)stringPosition:(NSString *)needle; // Performs literal comparison
- (void)enumerateMatchesOfString:(NSString *)string withBlock:(void (NS_NOESCAPE ^)(NSRange range, BOOL *stop))enumerationBlock;
- (void)enumerateMatchesOfString:(NSString *)string withBlock:(void (NS_NOESCAPE ^)(NSRange range, BOOL *stop))enumerationBlock options:(NSStringCompareOptions)options;

- (void)enumerateMatchesOfRegularExpression:(NSString *)expression withBlock:(void (NS_NOESCAPE ^)(NSRange range, BOOL *stop))enumerationBlock;
- (void)enumerateMatchesOfRegularExpression:(NSString *)expression withBlock:(void (NS_NOESCAPE ^)(NSRange range, BOOL *stop))enumerationBlock options:(NSStringCompareOptions)options;

- (void)enumerateFirstOccurrenceOfCharactersInString:(NSString *)string withBlock:(void (NS_NOESCAPE ^)(NSRange range, BOOL *stop))enumerationBlock;
- (void)enumerateFirstOccurrenceOfCharactersInString:(NSString *)string withBlock:(void (NS_NOESCAPE ^)(NSRange range, BOOL *stop))enumerationBlock options:(NSStringCompareOptions)options;

- (NSArray<NSString *> *)split:(NSString *)delimiter;
- (NSArray<NSString *> *)splitWithMaximumLength:(NSUInteger)maximumLength;

- (void)enumerateSplitOnNewLinesWithBlock:(void (NS_NOESCAPE ^)(NSString *sequence, BOOL *stop))enumerationBlock;

@property (readonly, copy) NSString *trim;
- (NSString *)trimCharacters:(NSString *)characters;

@property (readonly, copy) NSString *removeAllNewlines;

@property (getter=isAlphabeticNumericOnly, readonly) BOOL alphabeticNumericOnly; // a-z, A-Z, 0-9
@property (getter=isNumericOnly, readonly) BOOL numericOnly; // 0-9

@property (readonly) BOOL isPositiveWholeNumber;

/* When matching a number, if option to match positive
 or negative number is not specified, then positive is matched. */
- (BOOL)contentsIsOfType:(CSStringType)type;

@property (readonly, copy) NSString *safeFilename;

@property (readonly, copy) NSString *normalizeSpaces;

@property (readonly, copy, nullable) NSData *IPv4AddressBytes;
@property (readonly, copy, nullable) NSData *IPv6AddressBytes;

@property (getter=isIPv4Address, readonly) BOOL IPv4Address;
@property (getter=isIPv6Address, readonly) BOOL IPv6Address;
@property (getter=isIPAddress, readonly) BOOL IPAddress;

@property (readonly, copy) NSDictionary<NSString *, NSString *> *URLQueryItems;

/* Abstraction of query items that uses a custom
 separator and allows for custom decoding logic. */
/* Regular URL decoding is used by -formDataUsingSeparator: */
- (NSDictionary<NSString *, NSString *> *)formDataUsingSeparator:(NSString *)separator;
- (NSDictionary<NSString *, NSString *> *)formDataUsingSeparator:(NSString *)separator decodingBlock:(NSString *(NS_NOESCAPE ^)(NSString *value))decodingBlock;

/* Returns array of composed characters */
@property (readonly, copy) NSArray<NSString *> *characterStringBuffer;

/* First standardize path. See documentation for -stringByStandardizingPath
 for information on behavior. Then replaces home folder with tilde.
 Unlike -stringByAbbreviatingWithTildeInPath, for sandboxed apps, this will
 replace the user's actual home directory. Not the sandbox container home. */
@property (readonly, copy, nullable) NSString *standardizedTildePath;
@end

#pragma mark -
#pragma mark String Percent Encoding Helper

@interface NSString (CSStringPercentEncodingHelper)
@property (readonly, copy, nullable) NSString *percentEncodedString;
@property (readonly, copy, nullable) NSString *percentDecodedString;

@property (readonly, copy, nullable) NSString *percentEncodedURLPath;
@property (readonly, copy, nullable) NSString *percentEncodedURLQuery;
@end

#pragma mark
#pragma mark String Number Formatter Helper

@interface NSString (CSStringNumberHelper)
+ (NSString *)stringWithUniChar:(UniChar)value;
+ (NSString *)stringWithUnsignedShort:(unsigned short)value;
+ (NSString *)stringWithInteger:(NSInteger)value;
+ (NSString *)stringWithUnsignedInteger:(NSUInteger)value;
@end

#pragma mark 
#pragma mark Attributed String Helpers

@interface NSAttributedString (CSAttributedStringHelper)
@property (readonly, copy) NSDictionary<NSString *, id> *attributes;

@property (readonly) NSRange range;

+ (NSAttributedString *)attributedString;
+ (NSAttributedString *)attributedStringWithString:(NSString *)string;
+ (NSAttributedString *)attributedStringWithString:(NSString *)string attributes:(NSDictionary<NSString *, id> *)stringAttributes;

- (NSAttributedString *)attributedSubstringFromIndex:(NSUInteger)from;
@property (readonly, copy) NSArray<NSAttributedString *> *splitIntoLines;

- (BOOL)isAttributeSet:(NSString *)attribute atIndex:(NSUInteger)index;
- (BOOL)isAttributeSet:(NSString *)attribute atIndex:(NSUInteger)index attributeValue:(id _Nonnull * _Nullable)attributeValue;

- (BOOL)isAttributeSet:(NSString *)attribute inRange:(NSRange)range;
- (BOOL)isAttributeSet:(NSString *)attribute inRange:(NSRange)range attributeValue:(id _Nonnull * _Nullable)attributeValue;
@end

#pragma mark 
#pragma mark Mutable Attributed String Helpers

@interface NSMutableAttributedString (CSMutableAttributedStringHelper)
+ (NSMutableAttributedString *)mutableAttributedStringWithString:(NSString *)string;
+ (NSMutableAttributedString *)mutableAttributedStringWithString:(NSString *)string attributes:(NSDictionary<NSString *, id> *)stringAttributes;

@property (readonly, copy) NSString *trimmedString;

- (void)appendString:(NSString *)string;
- (void)appendString:(NSString *)string attributes:(NSDictionary<NSString *, id> *)stringAttributes;

- (void)addAttribute:(NSString *)attribute value:(id)value startingAt:(NSUInteger)index;
- (void)addAttributes:(NSDictionary<NSString *, id> *)attributes startingAt:(NSUInteger)index;

- (void)removeAttribute:(NSString *)attribute startingAt:(NSUInteger)index;

- (void)resetAttributesStaringAt:(NSUInteger)index;
@end

NS_ASSUME_NONNULL_END
