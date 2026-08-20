/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 *    Copyright (c) 2018 Codeux Software, LLC & respective contributors.
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
#import "TVCMainWindow.h"
#import "TVCAppearancePrivate.h"
#import "TVCMainWindowTextViewAppearancePrivate.h"

NS_ASSUME_NONNULL_BEGIN

@interface TVCMainWindowTextViewAppearance ()
#pragma mark -
#pragma mark Text View

@property(nonatomic, assign, readwrite) NSSize textViewInset;
@property(nonatomic, copy, nullable, readwrite) NSColor *textViewTextColor;
@property(nonatomic, copy, nullable, readwrite) NSColor *textViewPlaceholderTextColor;

@property(nonatomic, assign, readwrite) TVCMainWindowTextViewFontSize textViewPreferredFontSize;

#pragma mark -
#pragma mark Background View

@property(nonatomic, assign, readwrite) CGFloat backgroundViewContentBorderPadding;
@end

@implementation TVCMainWindowTextViewAppearance

#pragma mark -
#pragma mark Initialization

- (nullable instancetype)initWithWindow:(TVCMainWindow *)mainWindow
{
	NSParameterAssert(mainWindow != nil);

	NSURL *appearanceLocation = [self.class appearanceLocation];

	BOOL forRetinaDisplay = mainWindow.runningInHighResolutionMode;

	if ((self = [super initWithAppearanceAtURL:appearanceLocation forRetinaDisplay:forRetinaDisplay])) {
		[self prepareInitialState];

		return self;
	}

	return nil;
}

+ (NSURL *)appearanceLocation
{
	return [RZMainBundle() URLForResource:@"TVCMainWindowTextViewAppearance" withExtension:@"plist"];
}

- (void)prepareInitialState
{
	NSDictionary *properties = self.appearanceProperties;

	NSDictionary *textView = properties[@"Text View"];

	self.textViewInset = [self sizeInGroup:textView withKey:@"inset"];
	self.textViewTextColor = [self colorInGroup:textView withKey:@"normalTextColor"];
	self.textViewPlaceholderTextColor = [self colorInGroup:textView withKey:@"placeholderTextColor"];

	NSDictionary *backgroundView = properties[@"Background View"];

	self.backgroundViewContentBorderPadding = [self measurementInGroup:backgroundView withKey:@"contentBorderPadding"];

	[self flushAppearanceProperties];
}

#pragma mark -
#pragma mark Everything Else

- (BOOL)preferredTextViewFontChanged
{
	return (self.textViewPreferredFontSize != [TPCPreferences mainTextViewFontSize]);
}

- (nullable NSFont *)textViewPreferredFont
{
	TVCMainWindowTextViewFontSize preferredFontSize = [TPCPreferences mainTextViewFontSize];

	self.textViewPreferredFontSize = preferredFontSize;

	/* Sizes track the system text styles so they follow the
	 user's text size preferences rather than fixed point values. */
	switch (preferredFontSize) {
	case TVCMainWindowTextViewFontSizeLarge:
		return [NSFont preferredFontForTextStyle:NSFontTextStyleTitle3 options:@{}];
	case TVCMainWindowTextViewFontSizeExtraLarge:
		return [NSFont preferredFontForTextStyle:NSFontTextStyleTitle2 options:@{}];
	case TVCMainWindowTextViewFontSizeHumongous:
		return [NSFont preferredFontForTextStyle:NSFontTextStyleTitle1 options:@{}];
	default:
		return [NSFont preferredFontForTextStyle:NSFontTextStyleBody options:@{}];
	}
}

@end

NS_ASSUME_NONNULL_END
