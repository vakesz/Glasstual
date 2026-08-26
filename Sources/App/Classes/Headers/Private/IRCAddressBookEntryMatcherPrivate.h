/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

#import "IRCAddressBook.h"

NS_ASSUME_NONNULL_BEGIN

/* Owns the derived matching state for an address-book entry. The public
 configuration object remains Objective-C because AppKit binds to it directly.
 */
@interface IRCAddressBookEntryMatcher : NSObject
@property(readonly, copy) NSString *regularExpressionPattern;
@property(readonly, copy, nullable) NSString *trackingNickname;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithEntryType:(IRCAddressBookEntryType)entryType
                         hostmask:(NSString *)hostmask
    NS_DESIGNATED_INITIALIZER;

- (BOOL)matchesHostmask:(NSString *)hostmask;
@end

NS_ASSUME_NONNULL_END
