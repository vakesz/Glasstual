/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
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

NS_ASSUME_NONNULL_BEGIN

/**
 * A hyperlink located inside a string by TLOLinkParser
 */
@interface TLOLinkParserResult : NSObject
/**
 * Random identifier that is unique to this result
 */
@property(readonly, copy) NSString *uniqueIdentifier;

/**
 * The address of the link including its scheme.
 *
 * Scheme-less matches (such as "example.com") are prefixed with "http://"
 */
@property(readonly, copy) NSString *stringValue;

/**
 * The range of the match in the string that was scanned
 */
@property(readonly) NSRange range;

/**
 * YES when the match carried an explicit scheme.
 * NO for matches that were inferred from a bare domain name.
 */
@property(readonly) BOOL strictMatch;
@end

@interface TLOLinkParser : NSObject
/**
 * Locates hyperlinks in a string.
 *
 * Results are sorted by location and never overlap.
 */
+ (NSArray<TLOLinkParserResult *> *)locateLinksInString:(NSString *)string;

/**
 * Returns the string with a scheme prepended when it is a URL in
 * its entirety, or nil when the string is not a URL.
 */
+ (nullable NSString *)URLWithProperScheme:(NSString *)string;

@property(readonly, class, copy) NSArray<NSString *> *bannedLineTypes;
@end

NS_ASSUME_NONNULL_END
