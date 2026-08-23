#import <XCTest/XCTest.h>

#import "RCMSecureTransport.h"

@interface RCMSecureTransport (RCMSecureTransportTests)
+ (NSArray<NSNumber *> *)cipherSuitesInCollection:(RCMCipherSuiteCollection)collection
								includeDeprecated:(BOOL)includeDeprecated;
@end

@interface RCMSecureTransportTests : XCTestCase
@end

@implementation RCMSecureTransportTests

- (void)testCompatibilityCipherListIncludesDeprecatedSuites
{
	NSArray<NSNumber *> *cipherSuites =
		[RCMSecureTransport cipherSuitesInCollection:RCMCipherSuiteCollectionDefault includeDeprecated:YES];

	NSUInteger dheIndex = [cipherSuites indexOfObject:@(TLS_DHE_RSA_WITH_AES_256_GCM_SHA384)];
	NSUInteger rsaIndex = [cipherSuites indexOfObject:@(TLS_RSA_WITH_AES_256_GCM_SHA384)];

	XCTAssertNotEqual(dheIndex, NSNotFound);
	XCTAssertTrue([cipherSuites containsObject:@(TLS_RSA_WITH_AES_256_GCM_SHA384)]);
	XCTAssertLessThan(dheIndex, rsaIndex);
}

- (void)testModernCipherListExcludesDeprecatedSuites
{
	NSArray<NSNumber *> *cipherSuites =
		[RCMSecureTransport cipherSuitesInCollection:RCMCipherSuiteCollectionDefault includeDeprecated:NO];

	XCTAssertFalse([cipherSuites containsObject:@(TLS_RSA_WITH_AES_256_GCM_SHA384)]);
}

@end
