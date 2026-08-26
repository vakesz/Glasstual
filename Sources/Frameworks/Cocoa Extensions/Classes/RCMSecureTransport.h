/* *********************************************************************
 *
 *            Copyright (c) 2024 Codeux Software, LLC
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

// See the contents of RCMSecureTransport.m for additional license information.

#import <Security/Security.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, RCMCipherSuiteCollection) {
  RCMCipherSuiteCollectionDefault = 0,
  RCMCipherSuiteCollectionMozilla2015 = 1,
  RCMCipherSuiteCollectionMozilla2017 = 2,
  RCMCipherSuiteCollectionNone = 100
};

#define tls_protocol_version_unknown ((tls_protocol_version_t)0)
#define tls_ciphersuite_unknown ((tls_ciphersuite_t)0)

@interface RCMSecureTransport : NSObject
@property(class, readonly)
    tls_protocol_version_t minimumProtocolType; // TLS 1.2

+ (nullable NSString *)descriptionForProtocolType:
    (tls_protocol_version_t)protocolType;

/* Technically speaking, tls_ciphersuite_t and SSLCipherSuite
 are interchangeable since they refer to the same code points. */
+ (nullable NSString *)descriptionForCipherSuite:(tls_ciphersuite_t)cipherSuite;
+ (nullable NSString *)descriptionForCipherSuite:(tls_ciphersuite_t)cipherSuite
                                    withProtocol:(BOOL)appendProtocol;

+ (BOOL)isCipherSuiteDeprecated:(tls_ciphersuite_t)cipherSuite;

+ (NSArray<NSString *> *)descriptionsForCipherListCollection:
    (RCMCipherSuiteCollection)collection;
+ (NSArray<NSString *> *)
    descriptionsForCipherListCollection:(RCMCipherSuiteCollection)collection
                           withProtocol:(BOOL)appendProtocol;

+ (NSArray<NSNumber *> *)cipherSuitesInCollection:
    (RCMCipherSuiteCollection)collection;

+ (void)appendCipherSuitesInCollection:(RCMCipherSuiteCollection)collection
                     includeDeprecated:(BOOL)includeDeprecated
                             toOptions:(sec_protocol_options_t)protocolOptions;

+ (BOOL)isTLSError:(NSError *)error;
/* -descriptionForErrorCode: returns "Unknown" for out of range error codes */
+ (NSString *)descriptionForErrorCode:(NSInteger)errorCode;
+ (nullable NSString *)descriptionForBadCertificateErrorCode:
    (NSInteger)errorCode;
+ (BOOL)isBadCertificateErrorCode:(NSInteger)errorCode;

+ (nullable SecTrustRef)trustFromCertificateChain:
                            (NSArray<NSData *> *)certificateChain
                                   withPolicyName:(NSString *)policyName
    CF_RETURNS_RETAINED;

+ (nullable NSArray<NSData *> *)certificatesInTrust:(SecTrustRef)trustRef;
+ (nullable NSString *)policyNameInTrust:(SecTrustRef)trustRef;
@end

NS_ASSUME_NONNULL_END
