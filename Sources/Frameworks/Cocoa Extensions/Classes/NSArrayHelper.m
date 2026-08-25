/* *********************************************************************
 *
 *         Copyright (c) 2015 - 2020 Codeux Software, LLC
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

#include <objc/message.h>

NS_ASSUME_NONNULL_BEGIN

@implementation NSArray (CSArrayHelper)

- (NSUInteger)unsignedIntegerAtIndex:(NSUInteger)n
{
	@synchronized(self) {
		id object = self[n];

		if ([object respondsToSelector:@selector(unsignedIntegerValue)]) {
			return [object unsignedIntegerValue];
		}

		return 0;
	}
}

- (double)doubleAtIndex:(NSUInteger)n
{
	@synchronized(self) {
		id object = self[n];

		if ([object respondsToSelector:@selector(doubleValue)]) {
			return [object doubleValue];
		}

		return 0;
	}
}

- (BOOL)containsObjectIgnoringCase:(id)anObject
{
	NSParameterAssert(anObject != nil);

	if (self.count == 0) {
		return NO;
	}

	@synchronized(self) {
		NSUInteger objectIndex = [self indexOfObjectPassingTest:^BOOL(id object, NSUInteger index, BOOL *stop) {
			if ([object isEqualIgnoringCase:anObject]) {
				*stop = YES;

				return YES;
			} else {
				return NO;
			}
		}];

		return (objectIndex != NSNotFound);
	}
}

- (NSRange)range
{
	return NSMakeRange(0, self.count);
}

- (NSArray *)stringArrayControllerObjects
{
	if (self.count == 0) {
		return @[];
	}

	NSMutableArray *newSet = [NSMutableArray array];

	@synchronized(self) {
		[self enumerateObjectsUsingBlock:^(id object, NSUInteger index, BOOL *stop) {
			if ([object isKindOfClass:[NSString class]] == NO) {
				return;
			}

			[newSet addObject:@{@"string" : object}];
		}];
	}

	return [newSet copy];
}

- (NSArray *)arrayByRemovingEmptyValues
{
	return [self arrayByRemovingEmptyValues:YES trimming:NO uniquing:NO];
}

- (NSArray *)arrayByRemovingEmptyValuesAndUniquing
{
	return [self arrayByRemovingEmptyValues:YES trimming:NO uniquing:YES];
}

- (NSArray *)arrayByRemovingEmptyValues:(BOOL)removeEmptyValues trimming:(BOOL)trimValues uniquing:(BOOL)uniqueValues
{
	if (self.count == 0) {
		return self;
	}

	NSMutableArray *newArray = [NSMutableArray arrayWithCapacity:self.count];

	@synchronized(self) {
		[self enumerateObjectsUsingBlock:^(id object, NSUInteger index, BOOL *stop) {
			id objectValue = object;

			if (trimValues && [objectValue respondsToSelector:@selector(trim)]) {
				objectValue = [objectValue trim];
			}

			COCOA_EXTENSIONS_IGNORE_DEPRECATION_BEGIN
			if (removeEmptyValues && NSObjectIsEmpty(objectValue)) {
				COCOA_EXTENSIONS_IGNORE_DEPRECATION_END

				return;
			} else if (uniqueValues && [newArray containsObject:objectValue]) {
				return;
			}

			[newArray addObject:objectValue];
		}];

		return [newArray copy];
	}
}

- (nullable id)objectPassingTest:(BOOL(NS_NOESCAPE ^)(id object, NSUInteger index, BOOL *stop))predicate
{
	return [self objectPassingTest:predicate withOptions:0];
}

- (nullable id)objectPassingTest:(BOOL(NS_NOESCAPE ^)(id object, NSUInteger index, BOOL *stop))predicate
					 withOptions:(NSEnumerationOptions)options
{
	if (self.count == 0) {
		return nil;
	}

	NSUInteger objectIndex = [self indexOfObjectWithOptions:options passingTest:predicate];

	if (objectIndex == NSNotFound) {
		return nil;
	}

	return self[objectIndex];
}

- (void)enumerateSubarraysOfSize:(NSUInteger)subarraySize
					  usingBlock:(void(NS_NOESCAPE ^)(NSArray *objects, BOOL *stop))block
{
	[self enumerateSubarraysOfSize:subarraySize usingBlock:block withOptions:0];
}

- (void)enumerateSubarraysOfSize:(NSUInteger)subarraySize
					  usingBlock:(void(NS_NOESCAPE ^)(NSArray *objects, BOOL *stop))block
					 withOptions:(NSEnumerationOptions)options
{
	NSParameterAssert(subarraySize > 0);
	NSParameterAssert(block != nil);

	if (self.count == 0) {
		return;
	}

	NSMutableArray *subarray = [NSMutableArray arrayWithCapacity:subarraySize];

	@synchronized(self) {
		[self enumerateObjectsWithOptions:options
							   usingBlock:^(id object, NSUInteger index, BOOL *stop) {
								   [subarray addObject:object];

								   if (subarray.count == subarraySize) {
									   block([subarray copy], stop);

									   [subarray removeAllObjects];
								   }
							   }];
	}

	if (subarray.count > 0) {
		BOOL stop = NO;

		block([subarray copy], &stop);
	}
}

- (NSArray *)arrayByApplyingBlock:(id(NS_NOESCAPE ^)(id object, NSUInteger index, BOOL *stop))block
{
	return [self arrayByApplyingBlock:block withOptions:0];
}

- (NSArray *)arrayByApplyingBlock:(id(NS_NOESCAPE ^)(id object, NSUInteger index, BOOL *stop))block
					  withOptions:(NSEnumerationOptions)options
{
	NSParameterAssert(block != nil);

	if (self.count == 0) {
		return @[];
	}

	NSMutableArray *newArray = [NSMutableArray arrayWithCapacity:self.count];

	@synchronized(self) {
		[self enumerateObjectsWithOptions:options
							   usingBlock:^(id object, NSUInteger index, BOOL *stop) {
								   [newArray addObject:block(object, index, stop)];
							   }];
	}

	return [newArray copy];
}

@end

@implementation NSMutableArray (CSMutableArrayHelper)

- (void)addObjectWithoutDuplication:(id)anObject
{
	NSParameterAssert(anObject != nil);

	if ([self containsObject:anObject] == NO) {
		[self addObject:anObject];
	}
}

- (void)performSelectorOnObjectValueAndReplace:(SEL)performSelector
{
	NSParameterAssert(performSelector != NULL);

	if (self.count == 0) {
		return;
	}

	@synchronized(self) {
		NSArray *oldArray = [self copy];

		[oldArray enumerateObjectsUsingBlock:^(id object, NSUInteger index, BOOL *stop) {
#ifndef NS_BLOCK_ASSERTIONS
			NSMethodSignature *methodSignature = [object methodSignatureForSelector:performSelector];

			NSAssert1((*(methodSignature.methodReturnType) == '@'),
					  @"Selector '%@' does not return an object value",
					  NSStringFromSelector(performSelector));
#endif

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Warc-performSelector-leaks"
			id newObject = [object performSelector:performSelector];
#pragma GCC diagnostic pop

			NSAssert2((newObject != nil),
					  @"Object %@ returned a nil value when performing selector '%@'",
					  [object description],
					  NSStringFromSelector(performSelector));

			self[index] = newObject;
		}];
	}
}

- (void)shuffle
{
	if (self.count == 0) {
		return;
	}

	@synchronized(self) {
		NSUInteger selfCount = self.count;

		for (NSUInteger i = (selfCount - 1); i > 0; i--) {
			NSUInteger n = arc4random_uniform((uint32_t)i + 1);

			[self exchangeObjectAtIndex:i withObjectAtIndex:n];
		}
	}
}

- (void)moveObjectAtIndex:(NSUInteger)fromIndex toIndex:(NSUInteger)toIndex
{
	id object = self[fromIndex];

	[self removeObjectAtIndex:fromIndex];

	if (fromIndex < toIndex) {
		[self insertObject:object atIndex:(toIndex - 1)];
	} else {
		[self insertObject:object atIndex:toIndex];
	}
}

@end

NS_ASSUME_NONNULL_END
