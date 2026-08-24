/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

#import <XCTest/XCTest.h>

#import "TLOInternetAddressLookupPrivate.h"

NS_ASSUME_NONNULL_BEGIN

@interface TLOInternetAddressLookupDelegateSpy : NSObject <TLOInternetAddressLookupDelegate>
@end

@implementation TLOInternetAddressLookupDelegateSpy

- (void)internetAddressLookupReturnedAddress:(NSString *)address
{
}

- (void)internetAddressLookupFailed
{
}

@end

@interface TLOInternetAddressLookupTests : XCTestCase
@end

@implementation TLOInternetAddressLookupTests

- (NSHTTPURLResponse *)responseWithStatusCode:(NSInteger)statusCode
{
	return [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://example.invalid/address"]
									   statusCode:statusCode
									  HTTPVersion:@"HTTP/1.1"
									 headerFields:nil];
}

- (void)testAddressParserTrimsAndAcceptsEnabledIPv4
{
	NSData *data = [@"  203.0.113.42\n" dataUsingEncoding:NSUTF8StringEncoding];

	NSString *address = [TLOInternetAddressLookup addressFromData:data
														 response:[self responseWithStatusCode:200]
														allowIPv4:YES
														allowIPv6:NO];

	XCTAssertEqualObjects(address, @"203.0.113.42");
}

- (void)testAddressParserAcceptsEnabledIPv6
{
	NSData *data = [@"2001:db8::1" dataUsingEncoding:NSUTF8StringEncoding];

	NSString *address = [TLOInternetAddressLookup addressFromData:data
														 response:[self responseWithStatusCode:200]
														allowIPv4:NO
														allowIPv6:YES];

	XCTAssertEqualObjects(address, @"2001:db8::1");
}

- (void)testAddressParserRejectsDisabledOrMalformedAddresses
{
	NSHTTPURLResponse *response = [self responseWithStatusCode:200];
	NSData *IPv4Data = [@"203.0.113.42" dataUsingEncoding:NSUTF8StringEncoding];
	NSData *invalidData = [@"not an address" dataUsingEncoding:NSUTF8StringEncoding];

	XCTAssertNil([TLOInternetAddressLookup addressFromData:IPv4Data response:response allowIPv4:NO allowIPv6:YES]);
	XCTAssertNil([TLOInternetAddressLookup addressFromData:invalidData response:response allowIPv4:YES allowIPv6:YES]);
}

- (void)testAddressParserRejectsBadStatusAndOversizedResponse
{
	NSData *addressData = [@"203.0.113.42" dataUsingEncoding:NSUTF8StringEncoding];
	NSData *oversizedData = [NSMutableData dataWithLength:1025];

	XCTAssertNil([TLOInternetAddressLookup addressFromData:addressData
												  response:[self responseWithStatusCode:500]
												 allowIPv4:YES
												 allowIPv6:YES]);
	XCTAssertNil([TLOInternetAddressLookup addressFromData:oversizedData
												  response:[self responseWithStatusCode:200]
												 allowIPv4:YES
												 allowIPv6:YES]);
}

- (void)testLookupDefaultsToBothAddressFamilies
{
	TLOInternetAddressLookupDelegateSpy *delegate = [TLOInternetAddressLookupDelegateSpy new];
	TLOInternetAddressLookup *lookup = [[TLOInternetAddressLookup alloc] initWithDelegate:delegate];

	XCTAssertTrue(lookup.IPv4AddressIsValid);
	XCTAssertTrue(lookup.IPv6AddressIsValid);
}

@end

NS_ASSUME_NONNULL_END
