/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

#import "TLOInternetAddressLookup.h"

NS_ASSUME_NONNULL_BEGIN

@interface TLOInternetAddressLookup ()
+ (nullable NSString *)addressFromData:(nullable NSData *)data
							  response:(nullable NSURLResponse *)response
							 allowIPv4:(BOOL)allowIPv4
							 allowIPv6:(BOOL)allowIPv6;
@end

NS_ASSUME_NONNULL_END
