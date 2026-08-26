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

/* Welcome and identity: nickname, real name, alternate nickname. */
@interface TDCOnboardingIdentityStepViewController
    : TDCOnboardingStepViewController
@end

/* Look and feel: chat style, text size, appearance. */
@interface TDCOnboardingAppearanceStepViewController
    : TDCOnboardingStepViewController
@end

/* Notifications: what to notify about and the permission request. */
@interface TDCOnboardingNotificationsStepViewController
    : TDCOnboardingStepViewController
@end

/* First network: the network picker, auto-connect, suggested channels. */
@interface TDCOnboardingNetworkStepViewController
    : TDCOnboardingStepViewController
@end

/* A static mockup of a short conversation drawn with AppKit views, used to
 preview the "Bubbles" and "Lines" chat styles. */
@interface TDCOnboardingStylePreviewView : NSView
@property(nonatomic, copy) NSString *styleName;
@property(nonatomic, copy) NSString *styleTitle;
@property(nonatomic, copy) NSString *styleDescription;
@property(nonatomic, assign, getter=isSelected) BOOL selected;
@property(nonatomic, assign) CGFloat messageFontSize;
@property(nonatomic, weak, nullable) id target;
@property(nonatomic, assign, nullable) SEL action;
@end

NS_ASSUME_NONNULL_END
