/* ********************************************************************* 
                  _____         _               _
                 |_   _|____  _| |_ _   _  __ _| |
                   | |/ _ \ \/ / __| | | |/ _` | |
                   | |  __/>  <| |_| |_| | (_| | |
                   |_|\___/_/\_\\__|\__,_|\__,_|_|

 Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 Copyright (c) 2010 - 2015 Codeux Software, LLC & respective contributors.
        Please see Acknowledgements.pdf for additional information.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Textual and/or "Codeux Software, LLC", nor the 
      names of its contributors may be used to endorse or promote products 
      derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 SUCH DAMAGE.

 *********************************************************************** */

NS_ASSUME_NONNULL_BEGIN

@implementation TDCPreferencesSoundWrapper

+ (TDCPreferencesSoundWrapper *)soundWrapperWithEventType:(TXNotificationType)eventType
{
	return [[self alloc] initWithEventType:eventType];
}

- (NSString *)alertSound
{
	NSString *sound = [TPCPreferences soundForEvent:self.eventType];

	if (sound == nil) {
		return [TLONotificationConfiguration localizedAlertEmptySoundTitle];
	}

	return sound;
}

- (void)setAlertSound:(NSString *)alertSound
{
	[TPCPreferences setSound:alertSound forEvent:self.eventType];
}

- (BOOL)pushNotification
{
	return [TPCPreferences growlEnabledForEvent:self.eventType];
}

- (void)setPushNotification:(BOOL)pushNotification
{
	[TPCPreferences setGrowlEnabled:pushNotification forEvent:self.eventType];
}

- (BOOL)speakEvent
{
	return [TPCPreferences speakEvent:self.eventType];
}

- (void)setSpeakEvent:(BOOL)speakEvent
{
	[TPCPreferences setEventIsSpoken:speakEvent forEvent:self.eventType];
}

- (BOOL)disabledWhileAway
{
	return [TPCPreferences disabledWhileAwayForEvent:self.eventType];
}

- (void)setDisabledWhileAway:(BOOL)disabledWhileAway
{
	[TPCPreferences setDisabledWhileAway:disabledWhileAway forEvent:self.eventType];
}

- (BOOL)bounceDockIcon
{
	return [TPCPreferences bounceDockIconForEvent:self.eventType];
}

- (void)setBounceDockIcon:(BOOL)bounceDockIcon
{
	[TPCPreferences setBounceDockIcon:bounceDockIcon forEvent:self.eventType];
}

- (BOOL)bounceDockIconRepeatedly
{
	return [TPCPreferences bounceDockIconRepeatedlyForEvent:self.eventType];
}

- (void)setBounceDockIconRepeatedly:(BOOL)bounceDockIconRepeatedly
{
	[TPCPreferences setBounceDockIconRepeatedly:bounceDockIconRepeatedly forEvent:self.eventType];
}

@end

NS_ASSUME_NONNULL_END
