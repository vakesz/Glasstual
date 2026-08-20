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

/* A portion of this source file contains copyrighted work derived from one or more
 3rd party, open source projects. The use of this work is hereby acknowledged. */

// Copyright (c) 2005-2013 Mathias Karlsson
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// Please see LICENSE-GPLv2.txt for further information.

#import "BlowfishEncryptionKeyExchangeBase.h"

#import <CocoaExtensions/XRBase64Encoding.h>

/* OpenSSL Header Files. */
#include <openssl/sha.h>
#include <openssl/dh.h>
#include <openssl/bn.h>

#include <string.h>

/* Private Interface. */
@interface EKBlowfishEncryptionKeyExchangeBase ()
@property(nonatomic, strong) NSData *secretValue;
@property(nonatomic, unsafe_unretained) DH *DHStatus;
@property(nonatomic, unsafe_unretained) BIGNUM *publicBigNum;
@end

/* Static Values. */

/* 
	fishPrimeB64 is the exact value of the prime used by the original
	DH1080 implementation. DH->p and DH->g need to be the same value
	for each user involved in a Diffie-Hellman key exchange. Therefore,
	to ensure compatibility with existing users, we have used the same
	prime value (DH->p) as well as using "2" for DH->g. 

	DH1080Base also matches the Base64 format for encoding and decoding. 
*/
static NSString *fishPrimeB64 =
	@"++ECLiPSE+is+proud+to+present+latest+FiSH+release+featuring+even+more+security+for+you+++shouts+go+out+to+TMG+"
	@"for+helping+to+generate+this+cool+sophie+germain+prime+number++++/C32L";

/* Implementation. */
@implementation EKBlowfishEncryptionKeyExchangeBase

#pragma mark -

- (id)init
{
	if ((self = [super init])) {
		self.DHStatus = 0;

		self.publicBigNum = 0;

		if ([self initializeKeyExchange] == NO) {
			[self resetStatus];

			return nil;
		}

		return self;
	}

	return nil;
}

- (void)dealloc
{
	[self resetStatus];
	[self resetPublicInformation];
}

- (void)resetPublicInformation
{
	if (self.publicBigNum != 0) {
		BN_clear_free(self.publicBigNum);

		self.publicBigNum = 0;
	}
}

- (void)resetStatus
{
	if (self.DHStatus != 0) {
		DH_free(self.DHStatus);

		self.DHStatus = 0;
	}
}

#pragma mark -

- (BOOL)initializeKeyExchange
{
	if (self.DHStatus != 0) {
		return NO;
	}

	NSData *primeData = [self base64Decode:fishPrimeB64];

	if ([primeData length] < 1) {
		return NO;
	}

	DH *dh = DH_new();

	if (dh == 0) {
		return NO;
	}

	BIGNUM *g = BN_new();
	BIGNUM *p = BN_new();

	if (g == 0 || p == 0 || BN_dec2bn(&g, "2") == 0 ||
		BN_bin2bn((unsigned char *)[primeData bytes], (int)[primeData length], p) == 0) {
		BN_free(g);
		BN_free(p);
		DH_free(dh);

		return NO;
	}

	/* DH_set0_pqg() takes ownership of p and g on success. */
	if (DH_set0_pqg(dh, p, NULL, g) != 1) {
		BN_free(g);
		BN_free(p);
		DH_free(dh);

		return NO;
	}

	int codes = 0;

	if (DH_check(dh, &codes) != 1 || codes != 0) {
		DH_free(dh);

		return NO;
	}

	if (DH_generate_key(dh) != 1 || DH_size(dh) != EKBlowfishEncryptionKeyExchangeRequiredKeyLength) {
		DH_free(dh);

		return NO;
	}

	self.DHStatus = dh;

	return YES;
}

#pragma mark -

- (BOOL)computeKey
{
	self.secretValue = nil;

	if (self.DHStatus == 0 || self.publicBigNum == 0) {
		return NO;
	}

	int size = DH_size(self.DHStatus);

	if (size != EKBlowfishEncryptionKeyExchangeRequiredKeyLength) {
		return NO;
	}

	unsigned char key[EKBlowfishEncryptionKeyExchangeRequiredKeyLength];

	int num = DH_compute_key(key, self.publicBigNum, self.DHStatus);

	if (num <= 0 || num > size) {
		memset_s(key, sizeof(key), 0, sizeof(key));

		return NO;
	}

	/* DH_compute_key() strips leading zero bytes. Use the returned
	 length so the shared secret matches what the peer computes. */
	NSData *secretValue = [[NSData alloc] initWithBytes:key length:(NSUInteger)num];

	memset_s(key, sizeof(key), 0, sizeof(key));

	if ([secretValue length] < 1) {
		return NO;
	}

	self.secretValue = secretValue;

	return YES;
}

- (BOOL)setKeyForComputation:(NSData *)publicKey
{
	[self resetPublicInformation];

	if (self.DHStatus == 0 || [publicKey length] < 1) {
		return NO;
	}

	BIGNUM *peerKey = BN_bin2bn((unsigned char *)[publicKey bytes], (int)[publicKey length], NULL);

	if (peerKey == 0) {
		return NO;
	}

	/* DH_check_pub_key() rejects y <= 1 and y >= (p - 1). */
	int codes = 0;

	if (DH_check_pub_key(self.DHStatus, peerKey, &codes) != 1 || codes != 0) {
		BN_clear_free(peerKey);

		return NO;
	}

	self.publicBigNum = peerKey;

	return YES;
}

#pragma mark -

- (NSString *)secretStringValue
{
	NSData *secretValue = [self secretValue];

	if ([secretValue length] < 1) {
		return nil;
	}

	unsigned char sha_md[SHA256_DIGEST_LENGTH];

	SHA256((unsigned char *)[secretValue bytes], [secretValue length], sha_md);

	NSData *secretHash = [[NSData alloc] initWithBytes:sha_md length:sizeof(sha_md)];

	memset_s(sha_md, sizeof(sha_md), 0, sizeof(sha_md));

	return [self base64Encode:secretHash];
}

- (NSString *)publicKeyValue:(NSData *)publicInput
{
	if ([publicInput length] < 1) {
		return nil;
	}

	return [self base64Encode:publicInput];
}

- (NSData *)rawPublicKey
{
	if (self.DHStatus == 0) {
		return nil;
	}

	if (DH_size(self.DHStatus) != EKBlowfishEncryptionKeyExchangeRequiredKeyLength) {
		return nil;
	}

	const BIGNUM *publicKey = DH_get0_pub_key(self.DHStatus);

	if (publicKey == 0) {
		return nil;
	}

	unsigned char key[EKBlowfishEncryptionKeyExchangeRequiredKeyLength];

	/* Left pad with zeros so the wire format is always 135 bytes. */
	if (BN_bn2binpad(publicKey, key, sizeof(key)) != (int)sizeof(key)) {
		memset_s(key, sizeof(key), 0, sizeof(key));

		return nil;
	}

	NSData *publicInput = [[NSData alloc] initWithBytes:key length:sizeof(key)];

	memset_s(key, sizeof(key), 0, sizeof(key));

	return publicInput;
}

#pragma mark -

- (NSString *)base64Encode:(NSData *)input
{
	NSString *output = [XRBase64Encoding encodeData:input];

	if ([output length] < 1) {
		return nil;
	}

	BOOL equalFound = NO;

	while (YES) {
		NSRange equalRange = [output rangeOfString:@"="];

		if (equalRange.location == NSNotFound) {
			if (equalFound == NO) {
				output = [output stringByAppendingString:@"A"];
			}

			break;
		} else {
			equalFound = YES;

			output = [output substringWithRange:NSMakeRange(0, ([output length] - 1))];
		}
	}

	return output;
}

- (NSData *)base64Decode:(NSString *)input
{
	NSInteger inputLength = [input length];

	if (inputLength < 1) {
		return nil;
	}

	NSString *ecv = [input substringFromIndex:(inputLength - 1)];

	if ((inputLength % 4) == 1 && [ecv isEqualToString:@"A"]) {
		input = [input substringToIndex:(inputLength - 1)];
	}

	while ((([input length] % 4) == 0) == NO) {
		input = [input stringByAppendingString:@"="];
	}

	return [XRBase64Encoding decodeData:input];
}

@end
