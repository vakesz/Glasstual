/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
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

#import "TDCOnboardingStepViewController.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TDCOnboardingSettings

- (instancetype)init
{
	if ((self = [super init])) {
		self.nickname = @"";
		self.realName = @"";
		self.styleName = @"Bubbles";
		self.textSize = TDCOnboardingTextSizeMedium;
		self.appearance = TXPreferredAppearanceInherited;
		self.notifyOnHighlight = YES;
		self.notifyOnPrivateMessage = YES;
		self.playSounds = YES;
		self.connectWhenFinished = YES;
		self.channelsToJoin = @[];

		return self;
	}

	return nil;
}

+ (CGFloat)fontSizeForTextSize:(TDCOnboardingTextSize)textSize
{
	switch (textSize) {
	case TDCOnboardingTextSizeSmall: {
		return 11.0;
	}
	case TDCOnboardingTextSizeLarge: {
		return 15.0;
	}
	default: {
		return 13.0;
	}
	}
}

+ (TDCOnboardingTextSize)textSizeForFontSize:(CGFloat)fontSize
{
	if (fontSize < 12.0) {
		return TDCOnboardingTextSizeSmall;
	}

	if (fontSize > 14.0) {
		return TDCOnboardingTextSizeLarge;
	}

	return TDCOnboardingTextSizeMedium;
}

@end

#pragma mark -

@implementation TDCOnboardingStepViewController

- (instancetype)initWithSettings:(TDCOnboardingSettings *)settings
{
	NSParameterAssert(settings != nil);

	if ((self = [super initWithNibName:nil bundle:nil])) {
		self.settings = settings;

		return self;
	}

	return nil;
}

- (NSString *)stepTitle
{
	return @"";
}

- (NSString *)stepSubtitle
{
	return @"";
}

- (BOOL)skippable
{
	return YES;
}

- (void)stepWillAppear
{
}

- (BOOL)commitWithError:(NSString *_Nullable *_Nullable)errorDescription
{
	return YES;
}

- (nullable NSView *)preferredFirstResponder
{
	return nil;
}

- (NSView *)makeContentView
{
	NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 380)];

	view.translatesAutoresizingMaskIntoConstraints = NO;

	return view;
}

@end

NS_ASSUME_NONNULL_END
