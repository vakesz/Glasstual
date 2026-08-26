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

#import "TPCPreferencesLocal.h"

NS_ASSUME_NONNULL_BEGIN

@class IRCClientConfigMutable;

typedef NS_ENUM(NSUInteger, TDCOnboardingTextSize) {
  TDCOnboardingTextSizeSmall = 0,
  TDCOnboardingTextSizeMedium,
  TDCOnboardingTextSizeLarge
};

/* Everything the onboarding steps collect. Steps write into it as the user
 edits; the window applies it when the flow finishes. */
@interface TDCOnboardingSettings : NSObject
@property(nonatomic, copy) NSString *nickname;
@property(nonatomic, copy) NSString *realName;
@property(nonatomic, copy, nullable) NSString *alternateNickname;

@property(nonatomic, copy) NSString *styleName; // "Bubbles" or "Lines"
@property(nonatomic, assign) TDCOnboardingTextSize textSize;
@property(nonatomic, assign) TXPreferredAppearance appearance;

@property(nonatomic, assign) BOOL notifyOnHighlight;
@property(nonatomic, assign) BOOL notifyOnPrivateMessage;
@property(nonatomic, assign) BOOL playSounds;

@property(nonatomic, strong, nullable) IRCClientConfigMutable *clientConfig;
@property(nonatomic, assign) BOOL connectWhenFinished;
@property(nonatomic, copy) NSArray<NSString *> *channelsToJoin;

/* The font size (points) for a text size tier. */
+ (CGFloat)fontSizeForTextSize:(TDCOnboardingTextSize)textSize;
+ (TDCOnboardingTextSize)textSizeForFontSize:(CGFloat)fontSize;
@end

#pragma mark -

/* One page of the onboarding window. Subclasses build their view in
 -loadView and read/write the shared settings object. */
@interface TDCOnboardingStepViewController : NSViewController
@property(nonatomic, strong) TDCOnboardingSettings *settings;

@property(readonly, copy) NSString *stepTitle;
@property(readonly, copy) NSString *stepSubtitle;

/* Whether the Skip button is offered on this step. */
@property(readonly) BOOL skippable;

/* Called before the step is shown so that it can refresh from settings. */
- (void)stepWillAppear;

/* Called when the user presses Continue. Return NO and set the error to
 stay on the step. */
- (BOOL)commitWithError:(NSString *_Nullable *_Nullable)errorDescription;

/* The view that should receive focus when the step appears. */
@property(readonly, nullable) NSView *preferredFirstResponder;

- (instancetype)initWithSettings:(TDCOnboardingSettings *)settings;

/* A container view with a fixed size matching the window's content area.
 Subclasses call this from -loadView. */
- (NSView *)makeContentView;
@end

NS_ASSUME_NONNULL_END
