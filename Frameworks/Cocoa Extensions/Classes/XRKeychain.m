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

#import <Security/Security.h>

NS_ASSUME_NONNULL_BEGIN

@implementation XRKeychain

#pragma mark -
#pragma mark Queries

+ (NSMutableDictionary *)searchDictionary:(NSString *)itemName
							 withItemKind:(NSString *)itemKind
							  forUsername:(nullable NSString *)username
							  serviceName:(NSString *)service
{
	NSMutableDictionary *searchDictionary = [NSMutableDictionary dictionary];

	if ([itemKind isEqualToString:@"internet password"]) {
		searchDictionary[(id)kSecClass] = (id)kSecClassInternetPassword;
	} else {
		searchDictionary[(id)kSecClass] = (id)kSecClassGenericPassword;
	}

	searchDictionary[(id)kSecAttrLabel] = itemName;
	searchDictionary[(id)kSecAttrDescription] = itemKind;

	if (username.length > 0) {
		searchDictionary[(id)kSecAttrAccount] = username;
	}

	searchDictionary[(id)kSecAttrService] = service;

	return searchDictionary;
}

/* Query matching items in the legacy, file-based keychain only.

 Without kSecUseDataProtectionKeychain a query on macOS also matches items
 in the data protection keychain that belong to this app, so deleting a
 legacy item after migrating it would delete the migrated copy as well.
 Restricting the search to the default file-based keychain avoids that. */
+ (nullable NSMutableDictionary *)legacySearchDictionary:(NSString *)itemName
											withItemKind:(NSString *)itemKind
											 forUsername:(nullable NSString *)username
											 serviceName:(NSString *)service
{
	SecKeychainRef legacyKeychain = NULL;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	/* The file-based keychain API is deprecated. It is only used here to
	 scope the query so that items written by earlier versions can be
	 migrated out of it. */
	OSStatus status = SecKeychainCopyDefault(&legacyKeychain);
#pragma clang diagnostic pop

	if (status != errSecSuccess || legacyKeychain == NULL) {
		[self logStatus:status ofOperation:"legacy keychain lookup" forItem:itemName];

		return nil;
	}

	NSMutableDictionary *searchDictionary = [self searchDictionary:itemName
													  withItemKind:itemKind
													   forUsername:username
													   serviceName:service];

	searchDictionary[(id)kSecMatchSearchList] = @[ (__bridge_transfer id)legacyKeychain ];

	return searchDictionary;
}

/* Query matching items in the data protection keychain. */
+ (NSMutableDictionary *)protectedSearchDictionary:(NSString *)itemName
									  withItemKind:(NSString *)itemKind
									   forUsername:(nullable NSString *)username
									   serviceName:(NSString *)service
{
	NSMutableDictionary *searchDictionary = [self searchDictionary:itemName
													  withItemKind:itemKind
													   forUsername:username
													   serviceName:service];

	searchDictionary[(id)kSecUseDataProtectionKeychain] = (id)kCFBooleanTrue;

	return searchDictionary;
}

#pragma mark -
#pragma mark Logging

+ (void)logStatus:(OSStatus)status ofOperation:(const char *)operation forItem:(NSString *)itemName
{
	if (status == errSecSuccess) {
		return;
	}

	NSString *message = (__bridge_transfer NSString *)SecCopyErrorMessageString(status, NULL);

	if (status == errSecItemNotFound) {
		LogToConsoleDebugWithSubsystem(_CSFrameworkInternalLogSubsystem(),
			"Keychain %{public}s for “%{public}@” returned %{public}d: %{public}@",
			operation, itemName, (int)status, message);
	} else {
		LogToConsoleErrorWithSubsystem(_CSFrameworkInternalLogSubsystem(),
			"Keychain %{public}s for “%{public}@” failed with %{public}d: %{public}@",
			operation, itemName, (int)status, message);
	}
}

#pragma mark -
#pragma mark Delete

+ (BOOL)deleteKeychainItem:(NSString *)itemName
			  withItemKind:(NSString *)itemKind
			   forUsername:(nullable NSString *)username
			   serviceName:(NSString *)service
{
	NSParameterAssert(itemName != nil);
	NSParameterAssert(itemKind != nil);
	NSParameterAssert(service != nil);

	NSDictionary *dictionary = [self protectedSearchDictionary:itemName
												  withItemKind:itemKind
												   forUsername:username
												   serviceName:service];

	OSStatus status = SecItemDelete((__bridge CFDictionaryRef)dictionary);

	[self logStatus:status ofOperation:"delete" forItem:itemName];

	/* Delete any copy that may still exist in the legacy keychain
	 so that it is not resurrected by a later read-through. */
	[self deleteLegacyKeychainItem:itemName withItemKind:itemKind forUsername:username serviceName:service];

	return (status == errSecSuccess);
}

+ (BOOL)deleteLegacyKeychainItem:(NSString *)itemName
					withItemKind:(NSString *)itemKind
					 forUsername:(nullable NSString *)username
					 serviceName:(NSString *)service
{
	NSDictionary *dictionary = [self legacySearchDictionary:itemName
											   withItemKind:itemKind
												forUsername:username
												serviceName:service];

	if (dictionary == nil) {
		return NO;
	}

	OSStatus status = SecItemDelete((__bridge CFDictionaryRef)dictionary);

	[self logStatus:status ofOperation:"legacy delete" forItem:itemName];

	return (status == errSecSuccess);
}

#pragma mark -
#pragma mark Modify

+ (BOOL)modifyOrAddKeychainItem:(NSString *)itemName
				   withItemKind:(NSString *)itemKind
					forUsername:(nullable NSString *)username
				withNewPassword:(nullable NSString *)newPassword
					serviceName:(NSString *)service
{
	NSParameterAssert(itemName != nil);
	NSParameterAssert(itemKind != nil);
	NSParameterAssert(service != nil);

	NSDictionary *oldDictionary = [self protectedSearchDictionary:itemName
													 withItemKind:itemKind
													  forUsername:username
													  serviceName:service];

	NSMutableDictionary *newDictionary = [NSMutableDictionary dictionary];

	if (newPassword) {
		NSData *encodedPassword = [newPassword dataUsingEncoding:NSUTF8StringEncoding];

		newDictionary[(id)kSecValueData] = encodedPassword;
	}

	newDictionary[(id)kSecAttrAccessible] = (id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;

	OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)oldDictionary,
									(__bridge CFDictionaryRef)newDictionary);

	[self logStatus:status ofOperation:"update" forItem:itemName];

	if (status == errSecItemNotFound) {
		if (newPassword && newPassword.length > 0) {
			return [self addKeychainItem:itemName
							withItemKind:itemKind
							 forUsername:username
							withPassword:newPassword
							 serviceName:service];
		}
	}

	return (status == errSecSuccess);
}

#pragma mark -
#pragma mark Add

+ (BOOL)addKeychainItem:(NSString *)itemName
		   withItemKind:(NSString *)itemKind
			forUsername:(nullable NSString *)username
		   withPassword:(NSString *)password
			serviceName:(NSString *)service
{
	NSParameterAssert(itemName != nil);
	NSParameterAssert(itemKind != nil);
	NSParameterAssert(password != nil);
	NSParameterAssert(service != nil);

	NSMutableDictionary *dictionary = [self protectedSearchDictionary:itemName
														 withItemKind:itemKind
														  forUsername:username
														  serviceName:service];

	dictionary[(id)kSecAttrAccessible] = (id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;

	NSData *encodedPassword = [password dataUsingEncoding:NSUTF8StringEncoding];

	dictionary[(id)kSecValueData] = encodedPassword;

	OSStatus status = SecItemAdd((__bridge CFDictionaryRef)dictionary, NULL);

	[self logStatus:status ofOperation:"add" forItem:itemName];

	/* The legacy copy (if any) is superseded by the item just written. */
	if (status == errSecSuccess) {
		[self deleteLegacyKeychainItem:itemName withItemKind:itemKind forUsername:username serviceName:service];
	}

	return (status == errSecSuccess);
}

#pragma mark -
#pragma mark Read

+ (nullable NSString *)getPasswordFromKeychainItem:(NSString *)itemName
									  withItemKind:(NSString *)itemKind
									   forUsername:(nullable NSString *)username
									   serviceName:(NSString *)service
{
	return [self getPasswordFromKeychainItem:itemName
								withItemKind:itemKind
								 forUsername:username
								 serviceName:service
						  returnedStatusCode:NULL];
}

+ (nullable NSString *)getPasswordFromKeychainItem:(NSString *)itemName
									  withItemKind:(NSString *)itemKind
									   forUsername:(nullable NSString *)username
									   serviceName:(NSString *)service
								returnedStatusCode:(OSStatus * _Nullable)statusCode
{
	NSParameterAssert(itemName != nil);
	NSParameterAssert(itemKind != nil);
	NSParameterAssert(service != nil);

	NSMutableDictionary *dictionary = [self protectedSearchDictionary:itemName
														 withItemKind:itemKind
														  forUsername:username
														  serviceName:service];

	OSStatus status = errSecSuccess;

	NSString *password = [self _passwordMatchingQuery:dictionary status:&status];

	[self logStatus:status ofOperation:"read" forItem:itemName];

	if (status == errSecItemNotFound) {
		password = [self _migrateLegacyKeychainItem:itemName
									   withItemKind:itemKind
										forUsername:username
										serviceName:service
											 status:&status];
	}

	if ( statusCode) {
		*statusCode = status;
	}

	return password;
}

+ (nullable NSString *)_passwordMatchingQuery:(NSMutableDictionary *)dictionary status:(OSStatus *)statusCode
{
	dictionary[(id)kSecMatchLimit] = (id)kSecMatchLimitOne;
	dictionary[(id)kSecReturnData] = (id)kCFBooleanTrue;

	CFDataRef result = NULL;

	OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)dictionary, (CFTypeRef *)&result);

	*statusCode = status;

	NSData *passwordData = (__bridge_transfer NSData *)result;

	if (passwordData == nil) {
		return nil;
	}

	return [NSString stringWithData:passwordData encoding:NSUTF8StringEncoding];
}

/* Read-through migration: look the item up in the legacy keychain and,
 when found, copy it into the data protection keychain and delete the
 legacy item. The legacy password is returned regardless of whether
 the copy succeeded so that the caller is not left without a value. */
+ (nullable NSString *)_migrateLegacyKeychainItem:(NSString *)itemName
									 withItemKind:(NSString *)itemKind
									  forUsername:(nullable NSString *)username
									  serviceName:(NSString *)service
										   status:(OSStatus *)statusCode
{
	NSMutableDictionary *dictionary = [self legacySearchDictionary:itemName
													  withItemKind:itemKind
													   forUsername:username
													   serviceName:service];

	if (dictionary == nil) {
		return nil;
	}

	OSStatus status = errSecSuccess;

	NSString *password = [self _passwordMatchingQuery:dictionary status:&status];

	[self logStatus:status ofOperation:"legacy read" forItem:itemName];

	*statusCode = status;

	if (password == nil) {
		return nil;
	}

	LogToConsoleWithSubsystem(_CSFrameworkInternalLogSubsystem(),
		"Migrating keychain item “%{public}@” to the data protection keychain", itemName);

	/* -addKeychainItem: deletes the legacy item on success. */
	[self addKeychainItem:itemName
			 withItemKind:itemKind
			  forUsername:username
			 withPassword:password
			  serviceName:service];

	return password;
}

@end

NS_ASSUME_NONNULL_END
