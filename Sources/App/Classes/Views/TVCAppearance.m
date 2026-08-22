/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2018 - 2020Codeux Software, LLC & respective contributors.
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

#import "NSObjectHelperPrivate.h"
#import "TVCAppearancePrivate.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, TVCListAppearanceColorType) {
	TVCListAppearanceColorTypeCalibratedWhite = 1, // <white value> [alpha]
	TVCListAppearanceColorTypeRGB = 2,			   // <r> <g> <b> [alpha]
	TVCListAppearanceColorTypeSystem = 3,		   // selector
};

@interface TVCAppearance ()
@property(nonatomic, copy, nullable, readwrite) NSDictionary<NSString *, id> *appearanceProperties;
@end

@implementation TVCAppearance

- (instancetype)init
{
	[self doesNotRecognizeSelector:_cmd];

	return nil;
}

- (nullable instancetype)initWithAppearanceNamed:(NSString *)appearanceName atURL:(NSURL *)appearanceLocation
{
	NSParameterAssert(appearanceName != nil);
	NSParameterAssert(appearanceLocation != nil);

	if ((self = [super init])) {
		if ([self _loadAppearanceNamed:appearanceName atURL:appearanceLocation] == NO) {
			return nil;
		}

		return self;
	}

	return nil;
}

- (BOOL)_loadAppearanceNamed:(NSString *)appearanceName atURL:(NSURL *)appearanceLocation
{
	NSParameterAssert(appearanceName != nil);
	NSParameterAssert(appearanceLocation != nil);

	/* Load file */
	NSDictionary *appearances = [NSDictionary dictionaryWithContentsOfURL:appearanceLocation];

	if (appearances == nil) {
		return NO;
	}

	/* Find the appearance */
	NSDictionary *appearance = [appearances dictionaryForKey:appearanceName];

	if (appearance == nil) {
		return NO;
	}

	/* Save appearance */
	self.appearanceProperties = appearance;

	return YES;
}

- (void)flushAppearanceProperties
{
	self.appearanceProperties = nil;
}

#pragma mark -
#pragma mark Utilities

- (nullable id)_valueForKey:(NSString *)key expectedType:(Class)expectedType
{
	NSDictionary *group = self.appearanceProperties;

	if (group == nil) {
		return nil;
	}

	return [self _valueInGroup:group withKey:key expectedType:expectedType];
}

- (nullable id)_valueInGroup:(NSDictionary<NSString *, id> *)group
					 withKey:(NSString *)key
				expectedType:(Class)expectedType
{
	NSParameterAssert(group != nil);
	NSParameterAssert(key != nil);

	id referenceObject = group[key];

	if (referenceObject == nil || [referenceObject isKindOfClass:expectedType] == NO) {
		return nil;
	}

	return referenceObject;
}

/* Stateful properties define "activeWindow" and "inactiveWindow" entries. */
- (nullable id)_statefulValue:(NSDictionary<NSString *, id> *)referenceObject
			  forActiveWindow:(BOOL)forActiveWindow
				 expectedType:(Class)expectedType
{
	NSParameterAssert(referenceObject != nil);

	NSString *stateKey = ((forActiveWindow) ? @"activeWindow" : @"inactiveWindow");

	id stateValue = referenceObject[stateKey];

	if (stateValue == nil || [stateValue isKindOfClass:expectedType] == NO) {
		return nil;
	}

	return stateValue;
}

/* Stateful dictionary properties may either define "activeWindow" and
 "inactiveWindow" entries, or be a plain dictionary which is then used
 for both states. Semantic system colors make the latter the norm. */
- (nullable NSDictionary<NSString *, id> *)_statefulDictionary:(NSDictionary<NSString *, id> *)referenceObject
											   forActiveWindow:(BOOL)forActiveWindow
{
	NSParameterAssert(referenceObject != nil);

	if (referenceObject[@"activeWindow"] == nil && referenceObject[@"inactiveWindow"] == nil) {
		return referenceObject;
	}

	return [self _statefulValue:referenceObject forActiveWindow:forActiveWindow expectedType:[NSDictionary class]];
}

#pragma mark -
#pragma mark Color

- (nullable NSColor *)colorForKey:(NSString *)key
{
	NSParameterAssert(key != nil);

	NSDictionary *group = self.appearanceProperties;

	if (group == nil) {
		return nil;
	}

	return [self colorInGroup:group withKey:key];
}

- (nullable NSColor *)colorInGroup:(NSDictionary<NSString *, id> *)group withKey:(NSString *)key
{
	NSParameterAssert(group != nil);
	NSParameterAssert(key != nil);

	NSDictionary *colorProperties = [self _valueInGroup:group withKey:key expectedType:[NSDictionary class]];

	if (colorProperties == nil) {
		return nil;
	}

	return [self _colorWithProperties:colorProperties];
}

- (nullable NSColor *)colorForKey:(NSString *)key forActiveWindow:(BOOL)forActiveWindow
{
	NSParameterAssert(key != nil);

	NSDictionary *group = self.appearanceProperties;

	if (group == nil) {
		return nil;
	}

	return [self colorInGroup:group withKey:key forActiveWindow:forActiveWindow];
}

- (nullable NSColor *)colorInGroup:(NSDictionary<NSString *, id> *)group
						   withKey:(NSString *)key
				   forActiveWindow:(BOOL)forActiveWindow
{
	NSParameterAssert(group != nil);
	NSParameterAssert(key != nil);

	NSDictionary *referenceObject = [self _valueInGroup:group withKey:key expectedType:[NSDictionary class]];

	if (referenceObject == nil) {
		return nil;
	}

	NSDictionary *colorProperties = [self _statefulDictionary:referenceObject forActiveWindow:forActiveWindow];

	if (colorProperties == nil) {
		return nil;
	}

	return [self _colorWithProperties:colorProperties];
}

- (nullable NSColor *)_colorWithProperties:(NSDictionary<NSString *, id> *)colorProperties
{
	NSParameterAssert(colorProperties != nil);

	NSString *colorValue = [colorProperties stringForKey:@"value"];

	if (colorValue == nil) {
		return nil;
	}

	TVCListAppearanceColorType colorType = [colorProperties unsignedIntegerForKey:@"type"];

	switch (colorType) {
	case TVCListAppearanceColorTypeCalibratedWhite: {
		NSArray *components = [colorValue componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

		if (components.count == 0) {
			return nil;
		}

		CGFloat white = [components doubleAtIndex:0];

		CGFloat alpha = 1.0;

		if (components.count == 2) {
			alpha = [components doubleAtIndex:1];
		}

		return [NSColor colorWithCalibratedWhite:white alpha:alpha];
	}
	case TVCListAppearanceColorTypeRGB: {
		NSArray *components = [colorValue componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

		if (components.count < 3) {
			return nil;
		}

		CGFloat red = [components doubleAtIndex:0];
		CGFloat green = [components doubleAtIndex:1];
		CGFloat blue = [components doubleAtIndex:2];

		CGFloat alpha = 1.0;

		if (components.count == 4) {
			alpha = [components doubleAtIndex:3];
		}

		return [NSColor calibratedColorWithRed:red green:green blue:blue alpha:alpha];
	}
	case TVCListAppearanceColorTypeSystem: {
		SEL selector = NSSelectorFromString(colorValue);

		if ([NSColor respondsToSelector:selector] == NO) {
			LogToConsoleError("Missing color: %{public}@", colorValue);

			return nil;
		}

		return [NSColor performSelector:selector];
	}
	} // switch()

	return nil;
}

#pragma mark -
#pragma mark Size

- (NSSize)sizeForKey:(NSString *)key
{
	NSParameterAssert(key != nil);

	NSDictionary *group = self.appearanceProperties;

	if (group == nil) {
		return NSZeroSize;
	}

	return [self sizeInGroup:group withKey:key];
}

- (NSSize)sizeInGroup:(NSDictionary<NSString *, id> *)group withKey:(NSString *)key
{
	NSDictionary *referenceObject = [self _valueInGroup:group withKey:key expectedType:[NSDictionary class]];

	if (referenceObject == nil) {
		return NSZeroSize;
	}

	CGFloat width = [referenceObject doubleForKey:@"width"];
	CGFloat height = [referenceObject doubleForKey:@"height"];

	return NSMakeSize(width, height);
}

#pragma mark -
#pragma mark Measurement

- (CGFloat)measurementForKey:(NSString *)key
{
	NSParameterAssert(key != nil);

	NSDictionary *group = self.appearanceProperties;

	if (group == nil) {
		return 0;
	}

	return [self measurementInGroup:group withKey:key];
}

- (CGFloat)measurementInGroup:(NSDictionary<NSString *, id> *)group withKey:(NSString *)key
{
	NSParameterAssert(group != nil);
	NSParameterAssert(key != nil);

	NSNumber *referenceObject = [self _valueInGroup:group withKey:key expectedType:[NSNumber class]];

	if (referenceObject == nil) {
		return 0;
	}

	return referenceObject.doubleValue;
}

@end

#pragma mark -
#pragma mark Application Appearance

@interface TVCApplicationAppearance ()
@property(nonatomic, strong) TXAppearancePropertyCollection *applicationProperties;
@end

@implementation TVCApplicationAppearance

DESIGNATED_INITIALIZER_EXCEPTION_BODY_BEGIN
- (nullable instancetype)initWithAppearanceNamed:(NSString *)appearanceName atURL:(NSURL *)appearanceLocation
{
	NSAssert(NO, @"Use -initWithAppearanceAtURL: instead");

	return nil;
}
DESIGNATED_INITIALIZER_EXCEPTION_BODY_END

- (nullable instancetype)initWithAppearanceAtURL:(NSURL *)appearanceLocation
{
	NSParameterAssert(appearanceLocation != nil);

	TXAppearancePropertyCollection *applicationProperties = [TXSharedApplication sharedAppearance].properties;

	NSString *appearanceName = applicationProperties.appearanceName;

	if ((self = [super initWithAppearanceNamed:appearanceName atURL:appearanceLocation])) {
		self.applicationProperties = applicationProperties;

		return self;
	}

	return nil;
}

- (nullable instancetype)initWithAppearanceAtURL:(NSURL *)appearanceLocation forRetinaDisplay:(BOOL)forRetinaDisplay
{
	return [self initWithAppearanceAtURL:appearanceLocation];
}

- (NSString *)appearanceName
{
	return self.applicationProperties.appearanceName;
}

- (TXAppearanceType)appearanceType
{
	return self.applicationProperties.appearanceType;
}

- (NSString *)shortAppearanceDescription
{
	return self.applicationProperties.shortAppearanceDescription;
}

- (BOOL)isDarkAppearance
{
	return self.applicationProperties.isDarkAppearance;
}

- (TXAppKitAppearanceTarget)appKitAppearanceTarget
{
	return self.applicationProperties.appKitAppearanceTarget;
}

- (nullable NSAppearance *)appKitAppearance
{
	return self.applicationProperties.appKitAppearance;
}

@end

NS_ASSUME_NONNULL_END
